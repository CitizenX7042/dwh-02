"""Loader helper unit tests (no database)."""

from __future__ import annotations

from uuid import UUID

import pytest

from danor_etl.extractor import apply_max_rows, enrich_rows
from danor_etl.loader import build_insert_sql, quote_ident
from danor_etl.table_config import work_table_name


def test_quote_ident_safe():
    assert quote_ident("Items") == "[Items]"
    with pytest.raises(ValueError):
        quote_ident("Items; DROP")


def test_build_insert_sql():
    sql = build_insert_sql("stage", "Items", ["ID", "ItemKey", "SourceSystem"])
    assert sql.startswith("INSERT INTO [stage].[Items]")
    assert sql.count("?") == 3


def test_apply_max_rows_select():
    sql = apply_max_rows("SELECT ID, ItemKey FROM dbo.Items", 100)
    assert sql.upper().startswith("SELECT TOP (100)")


def test_enrich_rows_appends_metadata():
    run_id = UUID("12345678-1234-1234-1234-1234567890ab")
    rows = enrich_rows([(1, "A")], source_system="DANOR13", run_id=run_id)
    assert rows[0][0] == 1
    assert rows[0][1] == "A"
    assert rows[0][2] == "DANOR13"
    assert str(rows[0][4]) == str(run_id)


def test_work_table_name_generation():
    name = work_table_name("Accounts", "11111111-2222-3333-4444-555555555555")
    assert name.startswith("_etl_work_Accounts_")
    assert "-" not in name
