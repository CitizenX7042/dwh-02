"""Read-only chunked extraction from SQL Server."""

from __future__ import annotations

import logging
from collections.abc import Iterator
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

import pyodbc

from danor_etl.safety import validate_readonly_select
from danor_etl.table_config import TableConfig

logger = logging.getLogger(__name__)


def apply_max_rows(sql: str, max_rows: int | None) -> str:
    """Wrap a validated SELECT with TOP for development limits."""
    if max_rows is None:
        return sql
    if max_rows <= 0:
        raise ValueError("max_rows must be positive when provided")
    body = sql.strip().rstrip(";")
    upper = body.lstrip().upper()
    if upper.startswith("SELECT"):
        # INSERT TOP after SELECT
        rest = body.lstrip()[6:].lstrip()
        if rest.upper().startswith("TOP"):
            return body
        return f"SELECT TOP ({int(max_rows)}) {rest}"
    if upper.startswith("WITH"):
        return (
            f"SELECT TOP ({int(max_rows)}) * FROM (\n{body}\n) AS _etl_limited"
        )
    raise ValueError("Cannot apply max_rows to non-SELECT SQL")


def iter_source_batches(
    conn: pyodbc.Connection,
    *,
    sql: str,
    table: TableConfig,
    chunk_size: int,
    max_rows: int | None,
    query_timeout: int,
) -> Iterator[tuple[list[str], list[tuple[Any, ...]]]]:
    """
    Stream source rows using a server-side cursor and fetchmany.
    Yields (column_names, rows) per chunk. Never uses fetchall for table loads.
    """
    safe_sql = validate_readonly_select(sql)
    limited_sql = apply_max_rows(safe_sql, max_rows)

    # pyodbc: arraysize controls fetchmany default; server-side via connection setting
    conn.timeout = query_timeout
    cursor = conn.cursor()
    try:
        # Prefer firehose/server cursor behavior for large scans when supported
        try:
            cursor.arraysize = chunk_size
        except Exception:
            pass

        logger.info(
            "Extracting source rows",
            extra={
                "operation": "extract",
                "table_name": table.name,
                "chunk_size": chunk_size,
                "max_rows": max_rows,
            },
        )
        cursor.execute(limited_sql)
        if cursor.description is None:
            raise RuntimeError(f"Source query returned no result set for {table.name}")

        column_names = [col[0] for col in cursor.description]
        expected = table.source_columns
        if [c.lower() for c in column_names] != [c.lower() for c in expected]:
            raise RuntimeError(
                f"Source column mismatch for {table.name}: "
                f"got {column_names}, expected {expected}"
            )

        while True:
            rows = cursor.fetchmany(chunk_size)
            if not rows:
                break
            # Convert pyodbc.Row to plain tuples; preserve None
            batch = [tuple(r) for r in rows]
            yield column_names, batch
    finally:
        cursor.close()


def enrich_rows(
    rows: list[tuple[Any, ...]],
    *,
    source_system: str,
    run_id: UUID,
    extracted_at: datetime | None = None,
) -> list[tuple[Any, ...]]:
    """Append SourceSystem, ExtractedAtUtc, EtlRunId to each source row."""
    ts = extracted_at or datetime.now(timezone.utc).replace(tzinfo=None)
    rid = str(run_id)
    return [tuple(row) + (source_system, ts, rid) for row in rows]
