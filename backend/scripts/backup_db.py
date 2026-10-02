"""Operational backup and recovery utility for NextAction PostgreSQL database."""

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import shutil
import subprocess
import sys

from app.core.config import settings


def get_backup_command(output_path: Path) -> list[str]:
    """Generate the pg_dump command list for producing a compressed logical backup."""
    pg_dump = shutil.which("pg_dump") or "pg_dump"
    return [
        pg_dump,
        "-h", settings.POSTGRES_SERVER,
        "-p", str(settings.POSTGRES_PORT),
        "-U", settings.POSTGRES_USER,
        "-F", "c",              # Custom compressed archive format
        "-b",                   # Include large objects
        "-v",                   # Verbose mode
        "-f", str(output_path),
        settings.POSTGRES_DB,
    ]


def get_restore_command(input_path: Path, target_db: str = None) -> list[str]:
    """Generate the pg_restore command list for restoring from a compressed logical backup."""
    pg_restore = shutil.which("pg_restore") or "pg_restore"
    db_name = target_db or settings.POSTGRES_DB
    return [
        pg_restore,
        "-h", settings.POSTGRES_SERVER,
        "-p", str(settings.POSTGRES_PORT),
        "-U", settings.POSTGRES_USER,
        "-d", db_name,
        "--clean",              # Clean (drop) database objects prior to outputting
        "--if-exists",          # Use IF EXISTS when dropping objects
        "--no-owner",           # Do not output commands to set ownership of objects
        "--no-privileges",      # Do not output commands to restore access privileges
        "-v",                   # Verbose
        str(input_path),
    ]


def create_backup(dest_dir: Path) -> Path:
    """Create a timestamped compressed backup file."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%SZ")
    filename = f"nextaction_backup_{timestamp}.dump"
    output_path = dest_dir / filename

    cmd = get_backup_command(output_path)
    env = os.environ.copy()
    env["PGPASSWORD"] = settings.POSTGRES_PASSWORD

    print(f"Creating logical backup: {output_path}...")
    try:
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)
        print("Backup created successfully.")
        return output_path
    except subprocess.CalledProcessError as e:
        print(f"Backup failed (exit {e.returncode}): {e.stderr}", file=sys.stderr)
        raise
    except FileNotFoundError:
        print("pg_dump utility not found in PATH. Ensure PostgreSQL client tools are installed.", file=sys.stderr)
        raise


def verify_backup_file(backup_path: Path) -> bool:
    """Verify that a backup file exists and has non-zero size."""
    if not backup_path.exists():
        return False
    size = backup_path.stat().st_size
    return size > 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="NextAction Database Backup Utility")
    parser.add_argument("--dry-run", action="store_true", help="Print backup commands without executing")
    parser.add_argument("--dest", type=str, default="./backups", help="Target backup directory")
    args = parser.parse_args()

    dest = Path(args.dest)
    if args.dry_run:
        sample_path = dest / "nextaction_backup_sample.dump"
        print("Dry run: Backup command:")
        print(" ".join(get_backup_command(sample_path)))
        print("\nDry run: Restore command:")
        print(" ".join(get_restore_command(sample_path, target_db="nextaction_restore_test")))
    else:
        created = create_backup(dest)
        print(f"Verified: {verify_backup_file(created)}")
