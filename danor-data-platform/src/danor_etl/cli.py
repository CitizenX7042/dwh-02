"""CLI entrypoint: python -m danor_etl.cli <command>."""

from __future__ import annotations

import argparse
import socket
import sys
from typing import Sequence

from danor_etl.audit import new_run_id
from danor_etl.connections import connect_source, connect_target, probe_source, probe_target
from danor_etl.locking import EtlFileLock, LockError
from danor_etl.logging_utils import bind_extra, setup_logging
from danor_etl.pipeline import load_table
from danor_etl.settings import SettingsError, load_settings
from danor_etl.table_config import (
    TableConfigError,
    load_reference_group,
    load_tables_config,
)


def _add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--log-level", default=None, help="Override ETL_LOG_LEVEL")
    parser.add_argument(
        "--extract-chunk-size",
        type=int,
        default=None,
        help="Override ETL_EXTRACT_CHUNK_SIZE",
    )
    parser.add_argument(
        "--insert-batch-size",
        type=int,
        default=None,
        help="Override ETL_INSERT_BATCH_SIZE",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="danor-etl",
        description="Portable DANOR13 → Azure SQL staging ETL (read-only source)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_src = sub.add_parser("test-source", help="Test read-only source connectivity")
    _add_common_args(p_src)

    p_tgt = sub.add_parser("test-target", help="Test Azure SQL target connectivity")
    _add_common_args(p_tgt)

    p_load = sub.add_parser("load-table", help="Full-replace load one configured table")
    p_load.add_argument("table", help="Logical table name from config/tables.yaml")
    p_load.add_argument("--max-rows", type=int, default=None)
    p_load.add_argument("--dry-run", action="store_true")
    p_load.add_argument(
        "--source-only",
        action="store_true",
        help="Dry-run extract without requiring Azure SQL settings",
    )
    _add_common_args(p_load)

    p_ref = sub.add_parser(
        "load-reference",
        help="Load DocumentsDef, Items, and Accounts in sequence",
    )
    p_ref.add_argument("--max-rows", type=int, default=None)
    p_ref.add_argument("--dry-run", action="store_true")
    p_ref.add_argument("--source-only", action="store_true")
    _add_common_args(p_ref)

    return parser


def cmd_test_source(args: argparse.Namespace) -> int:
    settings = load_settings(require_target=False)
    setup_logging(args.log_level or settings.etl.log_level, settings.etl.log_dir)
    if settings.source.database.upper() != "DANOR13":
        print(
            f"ERROR: SOURCE_SQL_DATABASE must be DANOR13 "
            f"(got {settings.source.database!r})",
            file=sys.stderr,
        )
        return 2
    conn = connect_source(settings.source, settings.etl)
    try:
        info = probe_source(conn)
    finally:
        conn.close()
    if str(info["database_name"]).upper() != "DANOR13":
        print(
            f"ERROR: Connected database is {info['database_name']!r}, expected DANOR13",
            file=sys.stderr,
        )
        return 2
    print("SOURCE CONNECTION OK")
    print(f"  database_name : {info['database_name']}")
    print(f"  login_name    : {info['login_name']}")
    print(f"  server_name   : {info['server_name']}")
    print(f"  runner_host   : {socket.gethostname()}")
    return 0


def cmd_test_target(args: argparse.Namespace) -> int:
    settings = load_settings(require_target=True)
    setup_logging(args.log_level or settings.etl.log_level, settings.etl.log_dir)
    assert settings.target is not None
    conn = connect_target(settings.target, settings.etl)
    try:
        info = probe_target(conn)
    finally:
        conn.close()
    print("TARGET CONNECTION OK")
    print(f"  database_name : {info['database_name']}")
    print(f"  login_name    : {info['login_name']}")
    print(f"  user_name     : {info['user_name']}")
    print(f"  schemas       : {', '.join(info['schemas']) or '(none)'}")
    print(f"  runner_host   : {socket.gethostname()}")
    missing = {"stage", "audit"} - set(info["schemas"])
    if missing:
        print(
            "WARNING: Missing schemas "
            f"{sorted(missing)}. Run sql/target/001_create_schemas.sql "
            "(and 002/003) before loading."
        )
        return 3
    return 0


def _load_one(
    settings,
    tables: dict,
    table_name: str,
    args: argparse.Namespace,
    *,
    parent_run_id=None,
) -> dict:
    if table_name not in tables:
        raise TableConfigError(
            f"Unknown table {table_name!r}. Known: {sorted(tables)}"
        )
    run_id = new_run_id()
    return load_table(
        settings,
        tables[table_name],
        run_id=run_id,
        parent_run_id=parent_run_id,
        max_rows=args.max_rows,
        dry_run=args.dry_run,
        source_only=getattr(args, "source_only", False),
        extract_chunk_size=args.extract_chunk_size,
        insert_batch_size=args.insert_batch_size,
    )


def cmd_load_table(args: argparse.Namespace) -> int:
    require_target = not (args.dry_run and args.source_only)
    if args.dry_run and args.source_only:
        require_target = False
    elif args.dry_run:
        # Prefer target for DryRunCompleted audit when configured
        require_target = False
    else:
        require_target = True

    settings = load_settings(require_target=require_target)
    if not args.dry_run and not settings.target:
        print("ERROR: Target settings required for load-table", file=sys.stderr)
        return 2

    log = setup_logging(args.log_level or settings.etl.log_level, settings.etl.log_dir)
    tables = load_tables_config(settings.etl.project_root / "config" / "tables.yaml")

    lock = EtlFileLock(settings.etl.lock_dir)
    try:
        with lock:
            result = _load_one(settings, tables, args.table, args)
    except LockError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 4

    print(
        f"{result['status']}: {result['table']} "
        f"rows={result.get('target_row_count', result.get('source_row_count'))} "
        f"duration_s={result['duration_seconds']:.3f}"
    )
    log.info(
        "CLI finished",
        extra=bind_extra(
            table_name=result["table"],
            operation="cli",
            status=result["status"],
            row_count=result.get("target_row_count", result.get("source_row_count")),
            duration_seconds=result["duration_seconds"],
        ),
    )
    return 0


def cmd_load_reference(args: argparse.Namespace) -> int:
    require_target = not args.dry_run
    if args.dry_run and args.source_only:
        require_target = False
    elif args.dry_run:
        require_target = False
    settings = load_settings(require_target=require_target)
    if not args.dry_run and not settings.target:
        print("ERROR: Target settings required for load-reference", file=sys.stderr)
        return 2

    log = setup_logging(args.log_level or settings.etl.log_level, settings.etl.log_dir)
    cfg_path = settings.etl.project_root / "config" / "tables.yaml"
    tables = load_tables_config(cfg_path)
    group = load_reference_group(cfg_path)
    parent_id = new_run_id()

    lock = EtlFileLock(settings.etl.lock_dir)
    try:
        with lock:
            for name in group:
                result = _load_one(
                    settings, tables, name, args, parent_run_id=parent_id
                )
                print(
                    f"{result['status']}: {result['table']} "
                    f"rows={result.get('target_row_count', result.get('source_row_count'))} "
                    f"duration_s={result['duration_seconds']:.3f}"
                )
    except LockError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 4

    log.info(
        "Reference load finished",
        extra=bind_extra(operation="load_reference", status="Completed"),
    )
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "test-source":
            return cmd_test_source(args)
        if args.command == "test-target":
            return cmd_test_target(args)
        if args.command == "load-table":
            return cmd_load_table(args)
        if args.command == "load-reference":
            return cmd_load_reference(args)
        parser.error(f"Unknown command: {args.command}")
        return 2
    except SettingsError as exc:
        print(f"CONFIG ERROR: {exc}", file=sys.stderr)
        return 2
    except TableConfigError as exc:
        print(f"TABLE CONFIG ERROR: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        # Never print connection strings; type + message only
        print(f"ERROR: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
