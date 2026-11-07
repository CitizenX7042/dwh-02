"""Write ETL audit rows to Azure SQL only."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any
from uuid import UUID, uuid4

import pyodbc

logger = logging.getLogger(__name__)

STATUSES = (
    "Started",
    "Extracting",
    "Loading",
    "Validating",
    "Completed",
    "Failed",
    "DryRunCompleted",
)


def new_run_id() -> UUID:
    return uuid4()


def utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def insert_run(
    conn: pyodbc.Connection,
    *,
    run_id: UUID,
    table_name: str,
    load_mode: str,
    status: str,
    runner_host: str,
    source_system: str,
    parent_run_id: UUID | None = None,
    source_row_count: int | None = None,
    work_table_row_count: int | None = None,
    target_row_count: int | None = None,
    error_message: str | None = None,
    start_time: datetime | None = None,
    end_time: datetime | None = None,
) -> None:
    if status not in STATUSES:
        raise ValueError(f"Invalid audit status: {status}")
    start = start_time or utc_now()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO audit.EtlRun (
            RunId, ParentRunId, TableName, LoadMode, StartTimeUtc, EndTimeUtc,
            SourceRowCount, WorkTableRowCount, TargetRowCount, Status,
            ErrorMessage, RunnerHost, SourceSystem, CreatedAtUtc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, SYSUTCDATETIME())
        """,
        str(run_id),
        str(parent_run_id) if parent_run_id else None,
        table_name,
        load_mode,
        start,
        end_time,
        source_row_count,
        work_table_row_count,
        target_row_count,
        status,
        _truncate_error(error_message),
        runner_host,
        source_system,
    )
    conn.commit()


def update_run(
    conn: pyodbc.Connection,
    *,
    run_id: UUID,
    status: str,
    source_row_count: int | None = None,
    work_table_row_count: int | None = None,
    target_row_count: int | None = None,
    error_message: str | None = None,
    end_time: datetime | None = None,
) -> None:
    if status not in STATUSES:
        raise ValueError(f"Invalid audit status: {status}")
    cur = conn.cursor()
    cur.execute(
        """
        UPDATE audit.EtlRun
        SET Status = ?,
            SourceRowCount = COALESCE(?, SourceRowCount),
            WorkTableRowCount = COALESCE(?, WorkTableRowCount),
            TargetRowCount = COALESCE(?, TargetRowCount),
            ErrorMessage = COALESCE(?, ErrorMessage),
            EndTimeUtc = COALESCE(?, EndTimeUtc)
        WHERE RunId = ?
        """,
        status,
        source_row_count,
        work_table_row_count,
        target_row_count,
        _truncate_error(error_message),
        end_time,
        str(run_id),
    )
    conn.commit()


def try_record_failure(
    conn: pyodbc.Connection | None,
    *,
    run_id: UUID,
    error: BaseException,
) -> None:
    """Best-effort failure audit; never hides the original exception."""
    if conn is None:
        return
    try:
        update_run(
            conn,
            run_id=run_id,
            status="Failed",
            error_message=f"{type(error).__name__}: {error}",
            end_time=utc_now(),
        )
    except Exception as audit_exc:
        logger.error(
            "Failed to write audit failure row",
            extra={
                "operation": "audit_failure",
                "error_type": type(audit_exc).__name__,
            },
        )


def _truncate_error(message: str | None, limit: int = 4000) -> str | None:
    if message is None:
        return None
    # Scrub common secret patterns defensively
    scrubbed = message
    for token in ("PWD=", "Password=", "PASSWORD="):
        if token.lower() in scrubbed.lower():
            scrubbed = "Error details redacted because a secret-like token was detected"
            break
    if len(scrubbed) > limit:
        return scrubbed[: limit - 15] + "...[truncated]"
    return scrubbed
