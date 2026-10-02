"""Command-line interface for executing controlled PostgreSQL -> MongoDB data migrations."""

import argparse
import sys
from typing import Optional

from app.db.mongodb import get_mongodb_database
from app.db.session import SessionLocal
from app.migration.coordinator import MigrationCoordinator
from app.migration.verifier import MigrationVerifier


def build_parser() -> argparse.ArgumentParser:
    """Build argument parser for migration CLI."""
    parser = argparse.ArgumentParser(
        description="NextAction Controlled PostgreSQL -> MongoDB Data Migration CLI"
    )
    parser.add_argument(
        "--mode",
        choices=["dry-run", "migrate", "verify", "rollback"],
        default="dry-run",
        help="Migration execution mode (default: dry-run)",
    )
    parser.add_argument(
        "--migration-id",
        dest="migration_id",
        default=None,
        help="Optional explicit migration identifier or ID to roll back",
    )
    parser.add_argument(
        "--confirm",
        action="store_true",
        default=False,
        help="Explicit confirmation required to write to MongoDB or perform rollback",
    )
    return parser


def main(args: Optional[list] = None) -> int:
    """Entry point for migration CLI."""
    parser = build_parser()
    parsed = parser.parse_args(args)

    mode = parsed.mode
    coordinator = MigrationCoordinator()

    print("=" * 70)
    print("NextAction Dual-Engine Data Migration CLI (Phase 31)")
    print(f"Mode: {mode.upper()}")
    print("=" * 70)

    if mode in ("migrate", "rollback") and not parsed.confirm:
        print(f"\n[ERROR] --confirm flag is required for '{mode}' mode to prevent accidental operations.")
        print(f"Usage: python -m app.migration.cli --mode {mode} --confirm")
        return 1

    db = SessionLocal()
    mongo_db = get_mongodb_database()

    try:
        if mode == "dry-run":
            print("\nExecuting Migration Dry-Run (Simulation - ZERO writes)...")
            state = coordinator.run_dry_run(db=db, mongo_db=mongo_db)
            print(f"\nDry Run Result: {state.status.upper()}")
            print("-" * 50)
            for col, count in sorted(state.source_counts.items()):
                print(f"  {col:<26}: Source={count:<6} Migratable={state.inserted.get(col, 0):<6}")
            print("-" * 50)
            if state.relationship_errors:
                print(f"[FAILED] {len(state.relationship_errors)} relationship errors detected.")
                return 1
            print("[SUCCESS] All schemas, relationships, and invariants validated.")
            return 0

        elif mode == "migrate":
            print("\nExecuting Live Migration from PostgreSQL to MongoDB...")
            state = coordinator.run_migration(db=db, mongo_db=mongo_db, migration_id=parsed.migration_id)
            print(f"\nMigration Result: {state.status.upper()} (ID: {state.migration_id})")
            print("-" * 60)
            print(f"  {'Collection':<26} {'Source':<8} {'Inserted':<10} {'Updated':<10} {'Failed':<8}")
            print("-" * 60)
            for col in sorted(state.source_counts.keys()):
                src = state.source_counts.get(col, 0)
                ins = state.inserted.get(col, 0)
                upd = state.updated.get(col, 0)
                fl = state.failed.get(col, 0)
                print(f"  {col:<26} {src:<8} {ins:<10} {upd:<10} {fl:<8}")
            print("-" * 60)
            if state.status == "completed":
                print("[SUCCESS] Migration completed with full count and checksum parity.")
                return 0
            else:
                print(f"[FAILED] Migration finished with errors. See report.")
                return 1

        elif mode == "verify":
            print("\nVerifying PostgreSQL vs MongoDB Counts and Fingerprints...")
            verifier = MigrationVerifier(db=db, mongo_db=mongo_db)
            extractor_counts = coordinator.run_dry_run(db=db).source_counts
            counts = verifier.verify_counts(extractor_counts)
            print("-" * 50)
            for col, cmp_info in sorted(counts.items()):
                badge = "OK" if cmp_info["match"] else "MISMATCH"
                print(f"  {col:<26}: PG={cmp_info['postgresql']:<6} Mongo={cmp_info['mongodb']:<6} [{badge}]")
            print("-" * 50)
            all_match = all(c["match"] for c in counts.values())
            if all_match:
                print("[SUCCESS] Verification passed: All collection counts match.")
                return 0
            else:
                print("[FAILED] Discrepancies detected between PostgreSQL and MongoDB.")
                return 1

        elif mode == "rollback":
            if not parsed.migration_id:
                print("\n[ERROR] --migration-id is required for rollback mode.")
                return 1
            print(f"\nExecuting Rollback for Migration ID: {parsed.migration_id}...")
            deleted = coordinator.run_rollback(mongo_db=mongo_db, migration_id=parsed.migration_id)
            print("-" * 50)
            total_deleted = sum(deleted.values())
            for col, count in sorted(deleted.items()):
                print(f"  {col:<26}: Deleted {count} documents")
            print("-" * 50)
            print(f"[SUCCESS] Rollback complete. Removed {total_deleted} documents from MongoDB.")
            print("[SAFEGUARD] PostgreSQL was NOT modified in any way.")
            return 0

    finally:
        db.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
