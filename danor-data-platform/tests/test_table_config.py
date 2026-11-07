"""Table configuration parsing tests."""

from __future__ import annotations

from pathlib import Path

import pytest

from danor_etl.table_config import (
    TableConfigError,
    load_reference_group,
    load_tables_config,
    work_table_name,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONFIG = PROJECT_ROOT / "config" / "tables.yaml"


def test_load_project_tables_yaml():
    tables = load_tables_config(CONFIG)
    assert set(tables) == {"DocumentsDef", "Items", "Accounts"}
    items = tables["Items"]
    assert items.source_columns[0] == "ID"
    assert items.target_columns[-3:] == ["SourceSystem", "ExtractedAtUtc", "EtlRunId"]
    assert items.business_key == ["ItemKey"]
    assert items.load_mode == "full_replace"


def test_reference_group():
    assert load_reference_group(CONFIG) == ["DocumentsDef", "Items", "Accounts"]


def test_ordered_column_mapping_enforced(tmp_path):
    bad = tmp_path / "tables.yaml"
    bad.write_text(
        """
tables:
  DocumentsDef:
    source_schema: dbo
    source_table: DocumentsDef
    target_schema: stage
    target_table: DocumentsDef
    query_file: sql/source/DocumentsDef.sql
    business_key: [DocumentID]
    load_mode: full_replace
    source_columns: [DocumentID]
    target_columns: [DocumentID, Extra]
""",
        encoding="utf-8",
    )
    with pytest.raises(TableConfigError):
        load_tables_config(bad)


def test_work_table_name_uses_run_id():
    name = work_table_name("Items", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    assert name.startswith("_etl_work_Items_")
    assert "-" not in name
    assert "aaaaaaaa" in name
