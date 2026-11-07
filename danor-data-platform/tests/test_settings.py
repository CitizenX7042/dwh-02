"""Unit tests for settings parsing (no database)."""

from __future__ import annotations

import os

import pytest

from danor_etl.settings import (
    SettingsError,
    load_settings,
    parse_bool,
    parse_int,
)


def test_parse_bool_true_false():
    assert parse_bool("yes", name="x") is True
    assert parse_bool("0", name="x") is False
    assert parse_bool(None, default=True, name="x") is True
    with pytest.raises(SettingsError):
        parse_bool("maybe", name="x")


def test_parse_int():
    assert parse_int("42", name="n") == 42
    assert parse_int(None, default=7, name="n") == 7
    with pytest.raises(SettingsError):
        parse_int("abc", name="n")


def test_load_settings_requires_source(monkeypatch, tmp_path):
    monkeypatch.delenv("SOURCE_SQL_SERVER", raising=False)
    monkeypatch.delenv("SOURCE_SQL_PASSWORD", raising=False)
    # Ensure dotenv does not pick up a real .env from project during test
    monkeypatch.setenv("SOURCE_SQL_SERVER", "")
    with pytest.raises(SettingsError):
        load_settings(env_file=tmp_path / "missing.env", require_target=False)


def test_load_settings_source_only(monkeypatch, tmp_path):
    env = tmp_path / ".env"
    env.write_text(
        "\n".join(
            [
                "SOURCE_SQL_SERVER=sql-host",
                "SOURCE_SQL_DATABASE=DANOR13",
                "SOURCE_SQL_USERNAME=danor_etl_reader",
                "SOURCE_SQL_PASSWORD=secret",
                "SOURCE_SQL_ENCRYPT=no",
                "SOURCE_SQL_TRUST_SERVER_CERTIFICATE=yes",
                "ETL_EXTRACT_CHUNK_SIZE=1000",
            ]
        ),
        encoding="utf-8",
    )
    # Clear any ambient target vars
    for key in list(os.environ):
        if key.startswith("TARGET_") or key.startswith("SOURCE_") or key.startswith("ETL_"):
            monkeypatch.delenv(key, raising=False)

    settings = load_settings(env_file=env, require_target=False, dotenv_override=True)
    assert settings.source.server == "sql-host"
    assert settings.source.database == "DANOR13"
    assert settings.target is None
    assert settings.etl.extract_chunk_size == 1000
    summary = settings.source.safe_summary()
    assert "secret" not in summary["password"]
    assert summary["password"].startswith("s")


def test_load_settings_require_target(monkeypatch, tmp_path):
    env = tmp_path / ".env"
    env.write_text(
        "\n".join(
            [
                "SOURCE_SQL_SERVER=sql-host",
                "SOURCE_SQL_DATABASE=DANOR13",
                "SOURCE_SQL_USERNAME=danor_etl_reader",
                "SOURCE_SQL_PASSWORD=secret",
                "TARGET_SQL_SERVER=azure.database.windows.net",
                "TARGET_SQL_DATABASE=danor_dwh",
                "TARGET_SQL_USERNAME=etl_user",
                "TARGET_SQL_PASSWORD=target-secret",
            ]
        ),
        encoding="utf-8",
    )
    for key in list(os.environ):
        if key.startswith("TARGET_") or key.startswith("SOURCE_") or key.startswith("ETL_"):
            monkeypatch.delenv(key, raising=False)

    settings = load_settings(env_file=env, require_target=True, dotenv_override=True)
    assert settings.target is not None
    assert settings.target.encrypt is True
    assert settings.target.trust_server_certificate is False
    assert "target-secret" not in settings.target.safe_summary()["password"]
