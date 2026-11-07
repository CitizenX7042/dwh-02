"""Azure SQL staging loader with work-table full replacement."""

from __future__ import annotations

import logging
import re
from typing import Any, Sequence
from uuid import UUID

import pyodbc

from danor_etl.table_config import TableConfig, work_table_name

logger = logging.getLogger(__name__)

_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def quote_ident(name: str) -> str:
    if not _IDENT.match(name):
        raise ValueError(f"Unsafe SQL identifier: {name!r}")
    return f"[{name}]"


def qualified(schema: str, table: str) -> str:
    return f"{quote_ident(schema)}.{quote_ident(table)}"


def build_insert_sql(schema: str, table: str, columns: Sequence[str]) -> str:
    cols = ", ".join(quote_ident(c) for c in columns)
    placeholders = ", ".join("?" for _ in columns)
    return f"INSERT INTO {qualified(schema, table)} ({cols}) VALUES ({placeholders})"


def create_work_table(
    conn: pyodbc.Connection,
    *,
    table: TableConfig,
    run_id: UUID,
) -> str:
    """Create an empty work table cloning the final stage table definition."""
    work = work_table_name(table.target_table, str(run_id))
    final_q = qualified(table.target_schema, table.target_table)
    work_q = qualified(table.target_schema, work)
    cur = conn.cursor()
    # Drop leftover work table with same name (unlikely with UUID)
    cur.execute(
        f"IF OBJECT_ID(N'{table.target_schema}.{work}', N'U') IS NOT NULL "
        f"DROP TABLE {work_q}"
    )
    cur.execute(f"SELECT TOP (0) * INTO {work_q} FROM {final_q}")
    conn.commit()
    logger.info(
        "Created work table",
        extra={"operation": "create_work_table", "table_name": table.name, "work_table": work},
    )
    return work


def drop_work_table(conn: pyodbc.Connection, *, schema: str, work_table: str) -> None:
    if not _IDENT.match(work_table):
        raise ValueError(f"Unsafe work table name: {work_table!r}")
    cur = conn.cursor()
    cur.execute(
        f"IF OBJECT_ID(N'{schema}.{work_table}', N'U') IS NOT NULL "
        f"DROP TABLE {qualified(schema, work_table)}"
    )
    conn.commit()


def insert_batches(
    conn: pyodbc.Connection,
    *,
    schema: str,
    table_name: str,
    columns: Sequence[str],
    batches: list[list[tuple[Any, ...]]] | Any,
    batch_size: int,
) -> int:
    """
    Insert rows using fast_executemany.
    `batches` may be an iterator of row-lists or a prebuilt list.
    """
    sql = build_insert_sql(schema, table_name, columns)
    cur = conn.cursor()
    cur.fast_executemany = True
    total = 0
    buffer: list[tuple[Any, ...]] = []

    def flush() -> None:
        nonlocal buffer, total
        if not buffer:
            return
        cur.executemany(sql, buffer)
        total += len(buffer)
        buffer = []

    try:
        for batch in batches:
            for row in batch:
                buffer.append(row)
                if len(buffer) >= batch_size:
                    flush()
        flush()
        conn.commit()
        return total
    except Exception:
        try:
            conn.rollback()
        except Exception:
            pass
        raise


def count_rows(conn: pyodbc.Connection, schema: str, table_name: str) -> int:
    cur = conn.cursor()
    cur.execute(f"SELECT COUNT_BIG(*) FROM {qualified(schema, table_name)}")
    return int(cur.fetchone()[0])


def swap_work_into_stage(
    conn: pyodbc.Connection,
    *,
    table: TableConfig,
    work_table: str,
) -> int:
    """
    Replace final staging table contents from the validated work table
    inside a single connection transaction. Does not truncate before work
    load succeeds.
    """
    final_q = qualified(table.target_schema, table.target_table)
    work_q = qualified(table.target_schema, work_table)
    cols = ", ".join(quote_ident(c) for c in table.target_columns)

    cur = conn.cursor()
    try:
        cur.execute(f"TRUNCATE TABLE {final_q}")
        cur.execute(f"INSERT INTO {final_q} ({cols}) SELECT {cols} FROM {work_q}")
        cur.execute(f"SELECT COUNT_BIG(*) FROM {final_q}")
        target_count = int(cur.fetchone()[0])
        conn.commit()
        return target_count
    except Exception:
        try:
            conn.rollback()
        except Exception:
            pass
        raise


def cleanup_abandoned_work_tables(
    conn: pyodbc.Connection,
    *,
    schema: str = "stage",
    prefix: str = "_etl_work_",
) -> list[str]:
    """Best-effort cleanup of abandoned work tables from failed prior runs."""
    cur = conn.cursor()
    cur.execute(
        """
        SELECT t.name
        FROM sys.tables t
        INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = ? AND t.name LIKE ?
        """,
        schema,
        f"{prefix}%",
    )
    names = [r[0] for r in cur.fetchall()]
    dropped: list[str] = []
    for name in names:
        if not _IDENT.match(name):
            continue
        try:
            drop_work_table(conn, schema=schema, work_table=name)
            dropped.append(name)
        except Exception as exc:
            logger.warning(
                "Failed to drop abandoned work table",
                extra={"operation": "cleanup_work", "work_table": name, "error": type(exc).__name__},
            )
    return dropped
