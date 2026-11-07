"""ODBC connections. Never include secrets in exception messages."""

from __future__ import annotations

import logging
from typing import Any

import pyodbc

from danor_etl.settings import EtlSettings, SourceSettings, TargetSettings

logger = logging.getLogger(__name__)


class ConnectionErrorSafe(RuntimeError):
    """Connection failure without embedded secrets."""


def _yn(flag: bool | None) -> str | None:
    if flag is None:
        return None
    return "yes" if flag else "no"


def build_source_connection_string(source: SourceSettings, etl: EtlSettings) -> str:
    parts = [
        f"DRIVER={{{etl.driver}}}",
        f"SERVER={source.server},{source.port}" if source.port else f"SERVER={source.server}",
        f"DATABASE={source.database}",
        f"UID={source.username}",
        f"PWD={source.password}",
        f"ApplicationIntent={source.application_intent}",
        f"Connection Timeout={etl.connection_timeout_seconds}",
    ]
    enc = _yn(source.encrypt)
    if enc is not None:
        parts.append(f"Encrypt={enc}")
    trust = _yn(source.trust_server_certificate)
    if trust is not None:
        parts.append(f"TrustServerCertificate={trust}")
    return ";".join(parts)


def build_target_connection_string(target: TargetSettings, etl: EtlSettings) -> str:
    return ";".join(
        [
            f"DRIVER={{{etl.driver}}}",
            f"SERVER={target.server},{target.port}",
            f"DATABASE={target.database}",
            f"UID={target.username}",
            f"PWD={target.password}",
            f"Encrypt={_yn(target.encrypt)}",
            f"TrustServerCertificate={_yn(target.trust_server_certificate)}",
            f"Connection Timeout={etl.connection_timeout_seconds}",
        ]
    )


def _connect(conn_str: str, *, label: str, timeout: int) -> pyodbc.Connection:
    try:
        conn = pyodbc.connect(conn_str, timeout=timeout, autocommit=False)
        conn.timeout = timeout
        return conn
    except pyodbc.Error as exc:
        # Do not include the connection string or SQLSTATE details that may echo secrets.
        raise ConnectionErrorSafe(
            f"Failed to connect to {label}. Check host, network, driver, and credentials."
        ) from None


def connect_source(source: SourceSettings, etl: EtlSettings) -> pyodbc.Connection:
    logger.info(
        "Connecting to source",
        extra={
            "operation": "connect_source",
            "server": source.server,
            "database": source.database,
        },
    )
    return _connect(
        build_source_connection_string(source, etl),
        label="source SQL Server",
        timeout=etl.connection_timeout_seconds,
    )


def connect_target(target: TargetSettings, etl: EtlSettings) -> pyodbc.Connection:
    logger.info(
        "Connecting to target",
        extra={
            "operation": "connect_target",
            "server": target.server,
            "database": target.database,
        },
    )
    return _connect(
        build_target_connection_string(target, etl),
        label="Azure SQL target",
        timeout=etl.connection_timeout_seconds,
    )


def probe_source(conn: pyodbc.Connection) -> dict[str, Any]:
    cur = conn.cursor()
    cur.execute(
        "SELECT DB_NAME() AS database_name, "
        "SUSER_SNAME() AS login_name, "
        "@@SERVERNAME AS server_name"
    )
    row = cur.fetchone()
    return {
        "database_name": row.database_name,
        "login_name": row.login_name,
        "server_name": row.server_name,
    }


def probe_target(conn: pyodbc.Connection) -> dict[str, Any]:
    cur = conn.cursor()
    cur.execute(
        "SELECT DB_NAME() AS database_name, "
        "SUSER_SNAME() AS login_name, "
        "USER_NAME() AS user_name"
    )
    row = cur.fetchone()
    cur.execute(
        "SELECT name FROM sys.schemas WHERE name IN (N'stage', N'audit') ORDER BY name"
    )
    schemas = [r[0] for r in cur.fetchall()]
    return {
        "database_name": row.database_name,
        "login_name": row.login_name,
        "user_name": row.user_name,
        "schemas": schemas,
    }
