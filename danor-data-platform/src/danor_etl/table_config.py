"""Load and validate config/tables.yaml."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


class TableConfigError(ValueError):
    """Invalid table configuration."""


@dataclass(frozen=True)
class TableConfig:
    name: str
    description: str
    source_schema: str
    source_table: str
    target_schema: str
    target_table: str
    query_file: str
    business_key: list[str]
    load_mode: str
    source_columns: list[str]
    target_columns: list[str]
    default_max_rows: int | None

    @property
    def fully_qualified_source(self) -> str:
        return f"{self.source_schema}.{self.source_table}"

    @property
    def fully_qualified_target(self) -> str:
        return f"{self.target_schema}.{self.target_table}"


def _as_list(value: Any, *, field: str) -> list[str]:
    if value is None:
        raise TableConfigError(f"Missing list field: {field}")
    if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
        raise TableConfigError(f"Field {field} must be a list of strings")
    if not value:
        raise TableConfigError(f"Field {field} must not be empty")
    return list(value)


def load_tables_config(path: Path) -> dict[str, TableConfig]:
    if not path.is_file():
        raise TableConfigError(f"Table config not found: {path}")
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict) or "tables" not in raw:
        raise TableConfigError("tables.yaml must contain a top-level 'tables' mapping")

    defaults = raw.get("defaults") or {}
    tables: dict[str, TableConfig] = {}
    for name, cfg in raw["tables"].items():
        if not isinstance(cfg, dict):
            raise TableConfigError(f"Invalid table entry: {name}")
        source_columns = _as_list(cfg.get("source_columns"), field=f"{name}.source_columns")
        target_columns = _as_list(cfg.get("target_columns"), field=f"{name}.target_columns")
        # Target must start with source columns then metadata
        meta = ["SourceSystem", "ExtractedAtUtc", "EtlRunId"]
        expected = source_columns + meta
        if target_columns != expected:
            raise TableConfigError(
                f"{name}: target_columns must equal source_columns + {meta}"
            )
        tables[name] = TableConfig(
            name=name,
            description=str(cfg.get("description") or ""),
            source_schema=str(cfg.get("source_schema") or defaults.get("source_schema") or "dbo"),
            source_table=str(cfg.get("source_table") or name),
            target_schema=str(cfg.get("target_schema") or defaults.get("target_schema") or "stage"),
            target_table=str(cfg.get("target_table") or name),
            query_file=str(cfg.get("query_file") or ""),
            business_key=_as_list(cfg.get("business_key"), field=f"{name}.business_key"),
            load_mode=str(cfg.get("load_mode") or defaults.get("load_mode") or "full_replace"),
            source_columns=source_columns,
            target_columns=target_columns,
            default_max_rows=cfg.get("default_max_rows"),
        )
        if not tables[name].query_file:
            raise TableConfigError(f"{name}: query_file is required")
        if tables[name].load_mode != "full_replace":
            raise TableConfigError(f"{name}: only load_mode=full_replace is supported in PoC")
    return tables


def load_reference_group(path: Path) -> list[str]:
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    group = raw.get("reference_group") or []
    if not isinstance(group, list) or not all(isinstance(x, str) for x in group):
        raise TableConfigError("reference_group must be a list of table names")
    return list(group)


def resolve_query(project_root: Path, table: TableConfig) -> str:
    path = project_root / table.query_file
    if not path.is_file():
        raise TableConfigError(f"Query file not found for {table.name}: {path}")
    return path.read_text(encoding="utf-8")


def work_table_name(target_table: str, run_id: str) -> str:
    """
    Generate a unique work table name based on EtlRunId.
    Azure SQL identifiers max 128 chars; keep compact.
    """
    compact = run_id.replace("-", "")
    base = f"_etl_work_{target_table}_{compact}"
    if len(base) > 120:
        base = base[:120]
    return base
