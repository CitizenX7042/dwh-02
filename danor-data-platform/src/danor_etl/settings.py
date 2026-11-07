"""Environment-driven settings. Never log or expose secrets."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

TRUE_VALUES = {"1", "true", "yes", "y", "on"}
FALSE_VALUES = {"0", "false", "no", "n", "off", ""}


class SettingsError(ValueError):
    """Invalid or missing configuration."""


def _mask_secret(value: str | None) -> str:
    if value is None or value == "":
        return "<empty>"
    if len(value) <= 2:
        return "**"
    return f"{value[0]}***{value[-1]}"


def parse_bool(raw: str | None, *, default: bool | None = None, name: str = "value") -> bool:
    if raw is None or str(raw).strip() == "":
        if default is not None:
            return default
        raise SettingsError(f"Missing boolean setting: {name}")
    text = str(raw).strip().lower()
    if text in TRUE_VALUES:
        return True
    if text in FALSE_VALUES:
        return False
    raise SettingsError(f"Invalid boolean for {name}: {raw!r}")


def parse_int(raw: str | None, *, default: int | None = None, name: str = "value") -> int:
    if raw is None or str(raw).strip() == "":
        if default is not None:
            return default
        raise SettingsError(f"Missing integer setting: {name}")
    try:
        return int(str(raw).strip())
    except ValueError as exc:
        raise SettingsError(f"Invalid integer for {name}: {raw!r}") from exc


def require(name: str, value: str | None) -> str:
    if value is None or str(value).strip() == "":
        raise SettingsError(f"Missing required setting: {name}")
    return str(value).strip()


@dataclass(frozen=True)
class SourceSettings:
    server: str
    port: int | None
    database: str
    username: str
    password: str
    encrypt: bool | None
    trust_server_certificate: bool | None
    application_intent: str = "ReadOnly"

    def safe_summary(self) -> dict[str, Any]:
        return {
            "server": self.server,
            "port": self.port,
            "database": self.database,
            "username": self.username,
            "password": _mask_secret(self.password),
            "encrypt": self.encrypt,
            "trust_server_certificate": self.trust_server_certificate,
            "application_intent": self.application_intent,
        }


@dataclass(frozen=True)
class TargetSettings:
    server: str
    port: int
    database: str
    username: str
    password: str
    encrypt: bool
    trust_server_certificate: bool

    def safe_summary(self) -> dict[str, Any]:
        return {
            "server": self.server,
            "port": self.port,
            "database": self.database,
            "username": self.username,
            "password": _mask_secret(self.password),
            "encrypt": self.encrypt,
            "trust_server_certificate": self.trust_server_certificate,
        }


@dataclass(frozen=True)
class EtlSettings:
    source_system: str
    extract_chunk_size: int
    insert_batch_size: int
    query_timeout_seconds: int
    connection_timeout_seconds: int
    log_level: str
    log_dir: Path
    lock_dir: Path
    project_root: Path
    driver: str = "ODBC Driver 18 for SQL Server"


@dataclass(frozen=True)
class Settings:
    source: SourceSettings
    target: TargetSettings | None
    etl: EtlSettings

    @property
    def target_configured(self) -> bool:
        return self.target is not None


def _project_root() -> Path:
    # src/danor_etl/settings.py → parents[2] = project root
    return Path(__file__).resolve().parents[2]


def _optional_bool(name: str) -> bool | None:
    raw = os.getenv(name)
    if raw is None or str(raw).strip() == "":
        return None
    return parse_bool(raw, name=name)


def load_settings(
    *,
    env_file: str | Path | None = None,
    require_target: bool = False,
    dotenv_override: bool = False,
) -> Settings:
    """
    Load settings from environment (and optional .env file).

    Target settings may be omitted unless require_target=True
    (supports source-only dry-run).
    """
    root = _project_root()
    candidate = Path(env_file) if env_file else root / ".env"
    if candidate.is_file():
        load_dotenv(candidate, override=dotenv_override)
    else:
        load_dotenv(override=dotenv_override)

    source = SourceSettings(
        server=require("SOURCE_SQL_SERVER", os.getenv("SOURCE_SQL_SERVER")),
        port=parse_int(os.getenv("SOURCE_SQL_PORT"), default=0, name="SOURCE_SQL_PORT") or None,
        database=require("SOURCE_SQL_DATABASE", os.getenv("SOURCE_SQL_DATABASE")),
        username=require("SOURCE_SQL_USERNAME", os.getenv("SOURCE_SQL_USERNAME")),
        password=require("SOURCE_SQL_PASSWORD", os.getenv("SOURCE_SQL_PASSWORD")),
        encrypt=_optional_bool("SOURCE_SQL_ENCRYPT"),
        trust_server_certificate=_optional_bool("SOURCE_SQL_TRUST_SERVER_CERTIFICATE"),
    )

    target: TargetSettings | None = None
    target_server = os.getenv("TARGET_SQL_SERVER")
    if require_target or (target_server and str(target_server).strip()):
        target = TargetSettings(
            server=require("TARGET_SQL_SERVER", os.getenv("TARGET_SQL_SERVER")),
            port=parse_int(os.getenv("TARGET_SQL_PORT"), default=1433, name="TARGET_SQL_PORT"),
            database=require("TARGET_SQL_DATABASE", os.getenv("TARGET_SQL_DATABASE")),
            username=require("TARGET_SQL_USERNAME", os.getenv("TARGET_SQL_USERNAME")),
            password=require("TARGET_SQL_PASSWORD", os.getenv("TARGET_SQL_PASSWORD")),
            encrypt=parse_bool(
                os.getenv("TARGET_SQL_ENCRYPT"), default=True, name="TARGET_SQL_ENCRYPT"
            ),
            trust_server_certificate=parse_bool(
                os.getenv("TARGET_SQL_TRUST_SERVER_CERTIFICATE"),
                default=False,
                name="TARGET_SQL_TRUST_SERVER_CERTIFICATE",
            ),
        )

    log_dir_raw = os.getenv("ETL_LOG_DIR", "").strip()
    lock_dir_raw = os.getenv("ETL_LOCK_DIR", "").strip()
    etl = EtlSettings(
        source_system=os.getenv("ETL_SOURCE_SYSTEM", "DANOR13").strip() or "DANOR13",
        extract_chunk_size=parse_int(
            os.getenv("ETL_EXTRACT_CHUNK_SIZE"), default=5000, name="ETL_EXTRACT_CHUNK_SIZE"
        ),
        insert_batch_size=parse_int(
            os.getenv("ETL_INSERT_BATCH_SIZE"), default=5000, name="ETL_INSERT_BATCH_SIZE"
        ),
        query_timeout_seconds=parse_int(
            os.getenv("ETL_QUERY_TIMEOUT_SECONDS"),
            default=300,
            name="ETL_QUERY_TIMEOUT_SECONDS",
        ),
        connection_timeout_seconds=parse_int(
            os.getenv("ETL_CONNECTION_TIMEOUT_SECONDS"),
            default=30,
            name="ETL_CONNECTION_TIMEOUT_SECONDS",
        ),
        log_level=(os.getenv("ETL_LOG_LEVEL") or "INFO").strip().upper(),
        log_dir=Path(log_dir_raw) if log_dir_raw else root / "logs",
        lock_dir=Path(lock_dir_raw) if lock_dir_raw else root / "locks",
        project_root=root,
    )

    if etl.extract_chunk_size <= 0 or etl.insert_batch_size <= 0:
        raise SettingsError("ETL extract/insert batch sizes must be positive integers")

    return Settings(source=source, target=target, etl=etl)
