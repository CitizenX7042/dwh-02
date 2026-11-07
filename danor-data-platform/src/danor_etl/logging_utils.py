"""Structured logging helpers (never log secrets or row payloads)."""

from __future__ import annotations

import logging
import socket
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import UUID


class EtlLogFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        run_id = getattr(record, "etl_run_id", "-")
        table = getattr(record, "table_name", "-")
        operation = getattr(record, "operation", "-")
        rows = getattr(record, "row_count", "-")
        duration = getattr(record, "duration_seconds", "-")
        host = getattr(record, "runner_host", socket.gethostname())
        status = getattr(record, "status", "-")
        msg = record.getMessage()
        return (
            f"{ts} | {record.levelname} | run={run_id} | table={table} | "
            f"op={operation} | rows={rows} | duration_s={duration} | "
            f"host={host} | status={status} | {msg}"
        )


def setup_logging(level: str, log_dir: Path, *, run_id: UUID | None = None) -> logging.Logger:
    log_dir.mkdir(parents=True, exist_ok=True)
    root = logging.getLogger("danor_etl")
    root.handlers.clear()
    root.setLevel(getattr(logging, level.upper(), logging.INFO))

    formatter = EtlLogFormatter()
    stream = logging.StreamHandler()
    stream.setFormatter(formatter)
    root.addHandler(stream)

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    rid = str(run_id) if run_id else "norun"
    file_handler = logging.FileHandler(
        log_dir / f"etl_{stamp}_{rid[:8]}.log", encoding="utf-8"
    )
    file_handler.setFormatter(formatter)
    root.addHandler(file_handler)

    # Quiet noisy libraries
    logging.getLogger("pyodbc").setLevel(logging.WARNING)
    return root


def bind_extra(
    *,
    run_id: UUID | None = None,
    table_name: str | None = None,
    operation: str | None = None,
    row_count: int | None = None,
    duration_seconds: float | None = None,
    status: str | None = None,
    **more: Any,
) -> dict[str, Any]:
    extra: dict[str, Any] = {
        "etl_run_id": str(run_id) if run_id else "-",
        "table_name": table_name or "-",
        "operation": operation or "-",
        "row_count": row_count if row_count is not None else "-",
        "duration_seconds": (
            f"{duration_seconds:.3f}" if duration_seconds is not None else "-"
        ),
        "runner_host": socket.gethostname(),
        "status": status or "-",
    }
    extra.update(more)
    return extra
