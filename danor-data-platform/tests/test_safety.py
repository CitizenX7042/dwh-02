"""Source SQL safety tests (no database)."""

from __future__ import annotations

import pytest

from danor_etl.safety import UnsafeSqlError, validate_readonly_select


def test_allows_simple_select():
    sql = "SELECT DocumentID, DocName FROM dbo.DocumentsDef"
    assert validate_readonly_select(sql) == sql


def test_allows_with_select():
    sql = "WITH x AS (SELECT 1 AS a) SELECT a FROM x"
    assert "SELECT" in validate_readonly_select(sql).upper()


def test_rejects_insert():
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("INSERT INTO dbo.Items (ItemKey) VALUES ('x')")


def test_rejects_update_delete_merge():
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("UPDATE dbo.Items SET Price = 1")
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("DELETE FROM dbo.Items")
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("MERGE dbo.Items AS t USING dbo.Items AS s ON 1=1 WHEN MATCHED THEN DELETE;")


def test_rejects_exec():
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("EXEC dbo.GPRICE")
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("EXECUTE dbo.Zero")


def test_rejects_multiple_statements():
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("SELECT 1; SELECT 2")


def test_rejects_comments():
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("SELECT 1 -- comment")
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("SELECT 1 /* bypass */")


def test_rejects_select_into():
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("SELECT * INTO #t FROM dbo.Items")


def test_rejects_drop_truncate_create():
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("DROP TABLE dbo.Items")
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("TRUNCATE TABLE dbo.Items")
    with pytest.raises(UnsafeSqlError):
        validate_readonly_select("CREATE TABLE dbo.x (id int)")


def test_strips_trailing_semicolon():
    assert validate_readonly_select("SELECT 1;") == "SELECT 1"
