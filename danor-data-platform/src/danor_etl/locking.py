"""File-based single-runner lock (Windows-friendly, not distributed)."""

from __future__ import annotations

import json
import logging
import os
import socket
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)


class LockError(RuntimeError):
    """Raised when the ETL lock cannot be acquired."""


@dataclass
class LockInfo:
    pid: int
    hostname: str
    start_time_utc: str
    lock_path: str


class EtlFileLock:
    """Exclusive lock file for one ETL process on a single runner."""

    def __init__(self, lock_dir: Path, *, name: str = "danor_etl.lock", stale_seconds: int = 86400):
        self.lock_dir = Path(lock_dir)
        self.lock_path = self.lock_dir / name
        self.stale_seconds = stale_seconds
        self._held = False

    def acquire(self) -> LockInfo:
        self.lock_dir.mkdir(parents=True, exist_ok=True)
        if self.lock_path.exists():
            existing = self._read()
            if existing and self._pid_is_running(existing.pid):
                raise LockError(
                    f"Another ETL process appears active "
                    f"(pid={existing.pid}, host={existing.hostname}, "
                    f"started={existing.start_time_utc}). "
                    f"Lock file: {self.lock_path}"
                )
            # Stale or dead process — remove carefully
            age_ok = True
            if existing:
                try:
                    started = datetime.fromisoformat(existing.start_time_utc)
                    age = (datetime.now(timezone.utc) - started.replace(tzinfo=timezone.utc)).total_seconds()
                    # If started timestamp is weird, still allow replace when PID dead
                    age_ok = age >= 0
                except Exception:
                    age_ok = True
            logger.warning(
                "Removing stale ETL lock",
                extra={
                    "operation": "lock_stale_remove",
                    "lock_path": str(self.lock_path),
                    "previous_pid": existing.pid if existing else None,
                },
            )
            if age_ok:
                try:
                    self.lock_path.unlink(missing_ok=True)
                except OSError as exc:
                    raise LockError(f"Could not remove stale lock: {self.lock_path}") from exc

        info = LockInfo(
            pid=os.getpid(),
            hostname=socket.gethostname(),
            start_time_utc=datetime.now(timezone.utc).isoformat(),
            lock_path=str(self.lock_path),
        )
        # Exclusive create
        try:
            fd = os.open(str(self.lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError as exc:
            raise LockError(f"Lock already exists: {self.lock_path}") from exc
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "pid": info.pid,
                    "hostname": info.hostname,
                    "start_time_utc": info.start_time_utc,
                },
                fh,
                indent=2,
            )
        self._held = True
        logger.info(
            "Acquired ETL lock",
            extra={"operation": "lock_acquire", "pid": info.pid, "hostname": info.hostname},
        )
        return info

    def release(self) -> None:
        if not self._held:
            return
        try:
            if self.lock_path.exists():
                existing = self._read()
                if existing and existing.pid != os.getpid():
                    logger.warning(
                        "Lock file pid mismatch on release; leaving file in place",
                        extra={"operation": "lock_release_mismatch"},
                    )
                    return
                self.lock_path.unlink(missing_ok=True)
        finally:
            self._held = False
            logger.info("Released ETL lock", extra={"operation": "lock_release"})

    def __enter__(self) -> LockInfo:
        return self.acquire()

    def __exit__(self, exc_type, exc, tb) -> None:
        self.release()

    def _read(self) -> LockInfo | None:
        try:
            data = json.loads(self.lock_path.read_text(encoding="utf-8"))
            return LockInfo(
                pid=int(data["pid"]),
                hostname=str(data.get("hostname") or ""),
                start_time_utc=str(data.get("start_time_utc") or ""),
                lock_path=str(self.lock_path),
            )
        except Exception:
            return None

    @staticmethod
    def _pid_is_running(pid: int) -> bool:
        if pid <= 0:
            return False
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            # Process exists but we cannot signal it
            return True
        except OSError:
            # On Windows, invalid pid often raises OSError
            return False
        return True
