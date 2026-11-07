"""Orchestration for dry-run and full-replace table loads."""

from __future__ import annotations

import logging
import socket
import time
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from danor_etl import audit
from danor_etl.connections import connect_source, connect_target
from danor_etl.extractor import enrich_rows, iter_source_batches
from danor_etl.loader import (
    cleanup_abandoned_work_tables,
    count_rows,
    create_work_table,
    drop_work_table,
    insert_batches,
    swap_work_into_stage,
)
from danor_etl.logging_utils import bind_extra
from danor_etl.settings import Settings
from danor_etl.table_config import TableConfig, resolve_query

logger = logging.getLogger("danor_etl.pipeline")


class LoadError(RuntimeError):
    pass


def load_table(
    settings: Settings,
    table: TableConfig,
    *,
    run_id: UUID,
    parent_run_id: UUID | None = None,
    max_rows: int | None = None,
    dry_run: bool = False,
    source_only: bool = False,
    extract_chunk_size: int | None = None,
    insert_batch_size: int | None = None,
) -> dict[str, Any]:
    """
    Full-replace load into stage.<table> via a work table, or dry-run extract.
    """
    chunk = extract_chunk_size or settings.etl.extract_chunk_size
    insert_size = insert_batch_size or settings.etl.insert_batch_size
    host = socket.gethostname()
    sql = resolve_query(settings.etl.project_root, table)
    start = time.perf_counter()
    extracted_at = datetime.now(timezone.utc).replace(tzinfo=None)

    source_conn = connect_source(settings.source, settings.etl)
    target_conn = None
    work_table: str | None = None
    source_count = 0

    want_target = not source_only and (not dry_run or settings.target_configured)
    if want_target:
        if not settings.target:
            if dry_run:
                want_target = False
            else:
                raise LoadError("Target settings are required for non-dry-run loads")
        else:
            target_conn = connect_target(settings.target, settings.etl)

    try:
        if target_conn is not None:
            audit.insert_run(
                target_conn,
                run_id=run_id,
                parent_run_id=parent_run_id,
                table_name=table.name,
                load_mode="dry_run" if dry_run else table.load_mode,
                status="Started",
                runner_host=host,
                source_system=settings.etl.source_system,
                start_time=extracted_at,
            )
            if not dry_run:
                audit.update_run(target_conn, run_id=run_id, status="Extracting")

        logger.info(
            "Starting table load",
            extra=bind_extra(
                run_id=run_id,
                table_name=table.name,
                operation="start",
                status="Started",
            ),
        )

        if dry_run:
            for _cols, batch in iter_source_batches(
                source_conn,
                sql=sql,
                table=table,
                chunk_size=chunk,
                max_rows=max_rows,
                query_timeout=settings.etl.query_timeout_seconds,
            ):
                source_count += len(batch)
            duration = time.perf_counter() - start
            logger.info(
                "Dry-run extract completed",
                extra=bind_extra(
                    run_id=run_id,
                    table_name=table.name,
                    operation="dry_run",
                    row_count=source_count,
                    duration_seconds=duration,
                    status="DryRunCompleted",
                ),
            )
            if target_conn is not None:
                audit.update_run(
                    target_conn,
                    run_id=run_id,
                    status="DryRunCompleted",
                    source_row_count=source_count,
                    end_time=datetime.now(timezone.utc).replace(tzinfo=None),
                )
            return {
                "table": table.name,
                "status": "DryRunCompleted",
                "source_row_count": source_count,
                "duration_seconds": duration,
            }

        assert target_conn is not None
        cleanup_abandoned_work_tables(target_conn, schema=table.target_schema)
        work_table = create_work_table(target_conn, table=table, run_id=run_id)
        audit.update_run(target_conn, run_id=run_id, status="Loading")

        def batch_iter():
            nonlocal source_count
            for _cols, batch in iter_source_batches(
                source_conn,
                sql=sql,
                table=table,
                chunk_size=chunk,
                max_rows=max_rows,
                query_timeout=settings.etl.query_timeout_seconds,
            ):
                source_count += len(batch)
                enriched = enrich_rows(
                    batch,
                    source_system=settings.etl.source_system,
                    run_id=run_id,
                    extracted_at=extracted_at,
                )
                yield enriched

        loaded = insert_batches(
            target_conn,
            schema=table.target_schema,
            table_name=work_table,
            columns=table.target_columns,
            batches=batch_iter(),
            batch_size=insert_size,
        )

        audit.update_run(target_conn, run_id=run_id, status="Validating")
        work_count = count_rows(target_conn, table.target_schema, work_table)
        if work_count != source_count or loaded != source_count:
            raise LoadError(
                f"Row count mismatch for {table.name}: "
                f"extracted={source_count}, inserted={loaded}, work_table={work_count}"
            )

        target_count = swap_work_into_stage(
            target_conn, table=table, work_table=work_table
        )
        if target_count != source_count:
            raise LoadError(
                f"Post-swap count mismatch for {table.name}: "
                f"expected={source_count}, target={target_count}"
            )

        drop_work_table(target_conn, schema=table.target_schema, work_table=work_table)
        work_table = None

        duration = time.perf_counter() - start
        audit.update_run(
            target_conn,
            run_id=run_id,
            status="Completed",
            source_row_count=source_count,
            work_table_row_count=work_count,
            target_row_count=target_count,
            end_time=datetime.now(timezone.utc).replace(tzinfo=None),
        )
        logger.info(
            "Table load completed",
            extra=bind_extra(
                run_id=run_id,
                table_name=table.name,
                operation="load_complete",
                row_count=target_count,
                duration_seconds=duration,
                status="Completed",
            ),
        )
        return {
            "table": table.name,
            "status": "Completed",
            "source_row_count": source_count,
            "target_row_count": target_count,
            "duration_seconds": duration,
        }
    except Exception as exc:
        logger.error(
            "Table load failed",
            extra=bind_extra(
                run_id=run_id,
                table_name=table.name,
                operation="load_failed",
                row_count=source_count,
                duration_seconds=time.perf_counter() - start,
                status="Failed",
            ),
        )
        audit.try_record_failure(target_conn, run_id=run_id, error=exc)
        if target_conn is not None and work_table:
            try:
                drop_work_table(
                    target_conn, schema=table.target_schema, work_table=work_table
                )
            except Exception:
                logger.warning(
                    "Work table cleanup failed after error",
                    extra=bind_extra(
                        run_id=run_id,
                        table_name=table.name,
                        operation="cleanup_work_failed",
                        status="Failed",
                    ),
                )
        raise
    finally:
        try:
            source_conn.close()
        except Exception:
            pass
        if target_conn is not None:
            try:
                target_conn.close()
            except Exception:
                pass
