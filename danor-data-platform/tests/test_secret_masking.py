"""Secret masking / redaction tests."""

from __future__ import annotations

from danor_etl.audit import _truncate_error
from danor_etl.settings import SourceSettings


def test_source_safe_summary_masks_password():
    src = SourceSettings(
        server="host",
        port=1433,
        database="DANOR13",
        username="danor_etl_reader",
        password="SuperSecret!",
        encrypt=False,
        trust_server_certificate=True,
    )
    summary = src.safe_summary()
    assert "SuperSecret!" not in summary["password"]
    assert "***" in summary["password"]


def test_audit_error_redacts_pwd_token():
    msg = _truncate_error("Login failed; PWD=SuperSecret!; server=x")
    assert msg is not None
    assert "SuperSecret" not in msg
    assert "redacted" in msg.lower()
