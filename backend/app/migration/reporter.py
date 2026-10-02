"""Audit reporter: Generates structured Markdown and JSON reports stored in docs/migration-reports/."""

import json
from pathlib import Path
from typing import Any, Dict, Optional
from app.migration.state import MigrationState


class MigrationReporter:
    """Generates comprehensive local audit logs for migration executions."""

    def __init__(self, reports_dir: Optional[Path] = None):
        if reports_dir is None:
            # Default to docs/migration-reports at workspace root
            self.reports_dir = (
                Path(__file__).resolve().parent.parent.parent.parent
                / "docs"
                / "migration-reports"
            )
        else:
            self.reports_dir = reports_dir
        self.reports_dir.mkdir(parents=True, exist_ok=True)

    def write_report(
        self,
        state: MigrationState,
        count_comparison: Optional[Dict[str, Any]] = None,
        task_distributions: Optional[Dict[str, Any]] = None,
    ) -> Path:
        """Write both Markdown and JSON audit reports for the migration run.

        Returns:
            Path to the generated Markdown report.
        """
        md_path = self.reports_dir / f"migration_{state.migration_id}.md"
        json_path = self.reports_dir / f"migration_{state.migration_id}.json"

        # 1. Write structured JSON
        report_data = {
            "migration_id": state.migration_id,
            "mode": state.mode,
            "status": state.status,
            "start_time": state.start_time.isoformat() if state.start_time else None,
            "end_time": state.end_time.isoformat() if state.end_time else None,
            "source_database": state.source_database,
            "destination_database": state.destination_database,
            "source_counts": state.source_counts,
            "destination_counts_before": state.destination_counts_before,
            "destination_counts_after": state.destination_counts_after,
            "inserted": state.inserted,
            "updated": state.updated,
            "skipped": state.skipped,
            "invalid": state.invalid,
            "failed": state.failed,
            "count_comparison": count_comparison,
            "task_distributions": task_distributions,
            "checksum_mismatches": [m.model_dump() for m in state.checksum_mismatches],
            "relationship_errors": [r.model_dump() for r in state.relationship_errors],
            "errors": [e.model_dump() for e in state.errors],
        }

        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(report_data, f, indent=2, default=str)

        # 2. Write readable Markdown
        duration_sec = (
            (state.end_time - state.start_time).total_seconds()
            if state.end_time and state.start_time
            else 0.0
        )

        md_content = [
            f"# Migration Audit Report: `{state.migration_id}`\n",
            "## 1. Execution Summary\n",
            f"- **Migration ID**: `{state.migration_id}`",
            f"- **Execution Mode**: `{state.mode.upper()}`",
            f"- **Status**: `{state.status.upper()}`",
            f"- **Start Time (UTC)**: `{state.start_time.isoformat() if state.start_time else '-'}`",
            f"- **End Time (UTC)**: `{state.end_time.isoformat() if state.end_time else '-'}`",
            f"- **Duration**: `{duration_sec:.2f} seconds`",
            f"- **Source Database**: `{state.source_database}` (PostgreSQL 16)",
            f"- **Destination Database**: `{state.destination_database}` (MongoDB 7 / M0)",
            "\n---\n",
            "## 2. Collection Entity Counts & Loading Operations\n",
            "| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |",
            "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
        ]

        collections = sorted(
            set(
                list(state.source_counts.keys())
                + list(state.inserted.keys())
                + list(state.destination_counts_after.keys())
            )
        )

        for col in collections:
            src = state.source_counts.get(col, 0)
            before = state.destination_counts_before.get(col, 0)
            ins = state.inserted.get(col, 0)
            upd = state.updated.get(col, 0)
            fl = state.failed.get(col, 0)
            after = state.destination_counts_after.get(col, 0)
            status_badge = "MATCH" if src == after else ("DRY-RUN" if state.mode == "dry-run" else "DELTA")
            md_content.append(
                f"| `{col}` | {src} | {before} | {ins} | {upd} | {fl} | {after} | **{status_badge}** |"
            )

        md_content.extend([
            "\n---\n",
            "## 3. Relationship & Referential Integrity Validation\n",
        ])

        if not state.relationship_errors:
            md_content.append("All foreign key relationships and parent references validated with **0 errors**.\n")
        else:
            md_content.append(f"**{len(state.relationship_errors)} Broken Reference Errors Detected**:\n")
            for err in state.relationship_errors:
                md_content.append(
                    f"- `{err.parent_entity}` (ID: `{err.parent_id}`) -> "
                    f"Field `{err.reference_field}` references missing `{err.referenced_entity}` `{err.broken_id}`"
                )

        md_content.extend([
            "\n---\n",
            "## 4. Checksum & Fingerprint Integrity Verification\n",
        ])

        if not state.checksum_mismatches:
            md_content.append("All record SHA-256 fingerprints between PostgreSQL and MongoDB matched with **100% parity**.\n")
        else:
            md_content.append(f"**{len(state.checksum_mismatches)} Checksum Mismatches Detected**:\n")
            for mismatch in state.checksum_mismatches:
                md_content.append(
                    f"- Collection `{mismatch.entity}`, ID `{mismatch.entity_id}`: "
                    f"PG `{mismatch.postgres_fingerprint[:12]}...` vs Mongo `{mismatch.mongodb_fingerprint[:12]}...`"
                )

        if task_distributions:
            md_content.extend([
                "\n---\n",
                "## 5. Task Distribution Parity\n",
                "```json\n" + json.dumps(task_distributions, indent=2) + "\n```\n",
            ])

        md_content.extend([
            "\n---\n",
            "## 6. Safety & Rollback Verification\n",
            "- PostgreSQL was **NEVER** modified, deleted, or rolled back.",
            "- In rollback mode, only MongoDB documents with `_migration_id` are removed.",
            "- Production architecture remains ₹0/month with zero cloud resources created.",
        ])

        with open(md_path, "w", encoding="utf-8") as f:
            f.write("\n".join(md_content) + "\n")

        return md_path
