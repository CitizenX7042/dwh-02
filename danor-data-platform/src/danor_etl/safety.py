"""Defensive source SQL validator (additional guard; permissions remain primary)."""

from __future__ import annotations

import re

class UnsafeSqlError(ValueError):
    """Raised when source SQL fails the read-only safety checks."""


_FORBIDDEN = {
    "INSERT",
    "UPDATE",
    "DELETE",
    "MERGE",
    "TRUNCATE",
    "CREATE",
    "ALTER",
    "DROP",
    "EXEC",
    "EXECUTE",
    "GRANT",
    "REVOKE",
    "DENY",
    "INTO",
    "OPENROWSET",
    "OPENDATASOURCE",
    "BULK",
}


def validate_readonly_select(sql: str) -> str:
    """
    Validate that sql is a single read-only SELECT (optional leading WITH).

    Returns the trimmed original SQL if valid.
    """
    if sql is None:
        raise UnsafeSqlError("SQL is empty")

    original = sql.strip()
    if not original:
        raise UnsafeSqlError("SQL is empty")

    if "\x00" in original:
        raise UnsafeSqlError("SQL contains null bytes")

    # Reject comments entirely to prevent comment-bypass tricks
    if "--" in original or "/*" in original or "*/" in original:
        raise UnsafeSqlError("SQL comments are not allowed in source queries")

    body = original.rstrip()
    if body.endswith(";"):
        body = body[:-1].rstrip()
    if ";" in body:
        raise UnsafeSqlError("Multiple SQL statements are not allowed")

    if re.search(r"(?im)^\s*GO\s*$", body):
        raise UnsafeSqlError("Batch separator GO is not allowed")

    normalized = re.sub(r"\s+", " ", body).strip()
    upper = normalized.upper()

    if not (upper.startswith("SELECT") or upper.startswith("WITH")):
        raise UnsafeSqlError("Only SELECT or WITH…SELECT statements are allowed")

    if upper.startswith("WITH") and not re.search(r"\bSELECT\b", upper):
        raise UnsafeSqlError("WITH clause must end in a SELECT")

    tokens = re.findall(r"[A-Za-z_#][A-Za-z0-9_#]*", upper)
    for tok in tokens:
        if tok in _FORBIDDEN:
            raise UnsafeSqlError(f"Forbidden keyword in source SQL: {tok}")
        if tok.startswith("XP_") or tok.startswith("SP_"):
            raise UnsafeSqlError(f"Forbidden procedure-style token: {tok}")

    return body
