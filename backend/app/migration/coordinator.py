"""Migration coordinator: Orchestrates extraction, transformation, validation, loading, verification, and reporting."""

import logging
from typing import Any, Dict, List, Optional
from pymongo.database import Database
from sqlalchemy.orm import Session

from app.core.config import settings
from app.migration.extractor import PostgreSQLExtractor
from app.migration.loader import MIGRATION_ORDER, MongoDBLoader
from app.migration.reporter import MigrationReporter
from app.migration.rollback import MigrationRollback
from app.migration.state import MigrationError, MigrationState, generate_migration_id
from app.migration.transformer import EntityTransformer
from app.migration.validator import MigrationValidator
from app.migration.verifier import MigrationVerifier

logger = logging.getLogger("nextaction.migration")


class MigrationCoordinator:
    """Central orchestrator for PostgreSQL -> MongoDB data migrations."""

    def __init__(self, reporter: Optional[MigrationReporter] = None):
        self.reporter = reporter or MigrationReporter()

    def run_dry_run(self, db: Session, mongo_db: Optional[Database] = None) -> MigrationState:
        """Execute complete migration pipeline in simulation mode (ZERO writes).

        Extracts data from PostgreSQL, transforms into MongoDB schemas, validates relationships,
        calculates expected counts and detects any broken references without writing anything.
        """
        state = MigrationState(
            migration_id=generate_migration_id(),
            mode="dry-run",
            source_database="postgresql",
            destination_database="mongodb",
        )

        try:
            extractor = PostgreSQLExtractor(db)
            state.source_counts = extractor.get_source_counts()

            # Extract raw entities
            raw_entities = {
                "users": extractor.extract_users(),
                "user_settings": extractor.extract_user_settings(),
                "clients": extractor.extract_clients(),
                "workflows": extractor.extract_workflows(),
                "task_templates": extractor.extract_task_templates(),
                "recurring_tasks": extractor.extract_recurring_tasks(),
                "tasks": extractor.extract_tasks(),
                "task_history": extractor.extract_task_histories(),
                "recurring_task_executions": extractor.extract_recurring_task_executions(),
                "notifications": extractor.extract_notifications(),
                "events": extractor.extract_events(),
                "refresh_tokens": extractor.extract_refresh_tokens(),
            }

            # Validate relationships before transformation
            rel_errors = MigrationValidator.validate_relationships(raw_entities)
            state.relationship_errors.extend(rel_errors)

            # Transform entities
            transformed: Dict[str, List[Any]] = {}
            for u in raw_entities["users"]:
                transformed.setdefault("users", []).append(EntityTransformer.transform_user(u))
            for s in raw_entities["user_settings"]:
                transformed.setdefault("user_settings", []).append(
                    EntityTransformer.transform_user_settings(s)
                )
            for c in raw_entities["clients"]:
                transformed.setdefault("clients", []).append(EntityTransformer.transform_client(c))
            for w in raw_entities["workflows"]:
                transformed.setdefault("workflows", []).append(EntityTransformer.transform_workflow(w))
            for tt in raw_entities["task_templates"]:
                transformed.setdefault("task_templates", []).append(
                    EntityTransformer.transform_task_template(tt)
                )
            for rt in raw_entities["recurring_tasks"]:
                transformed.setdefault("recurring_tasks", []).append(
                    EntityTransformer.transform_recurring_task(rt)
                )
            for t in raw_entities["tasks"]:
                transformed.setdefault("tasks", []).append(EntityTransformer.transform_task(t))
            for h in raw_entities["task_history"]:
                transformed.setdefault("task_history", []).append(
                    EntityTransformer.transform_task_history(h)
                )
            for re in raw_entities["recurring_task_executions"]:
                transformed.setdefault("recurring_task_executions", []).append(
                    EntityTransformer.transform_recurring_task_execution(re)
                )
            for n in raw_entities["notifications"]:
                transformed.setdefault("notifications", []).append(
                    EntityTransformer.transform_notification(n)
                )
            for ev in raw_entities["events"]:
                transformed.setdefault("events", []).append(EntityTransformer.transform_event(ev))
            for tok in raw_entities["refresh_tokens"]:
                transformed.setdefault("refresh_tokens", []).append(
                    EntityTransformer.transform_refresh_token(tok)
                )

            # Calculate migratable counts
            for col in MIGRATION_ORDER:
                docs = transformed.get(col, [])
                state.inserted[col] = len(docs)
                state.updated[col] = 0
                state.failed[col] = 0

            if mongo_db is not None:
                verifier = MigrationVerifier(db, mongo_db)
                state.destination_counts_before = verifier.get_mongodb_counts()
                state.destination_counts_after = dict(state.destination_counts_before)

            if state.relationship_errors:
                state.mark_failed(
                    f"Dry run identified {len(state.relationship_errors)} referential integrity violations."
                )
            else:
                state.mark_completed()

            self.reporter.write_report(state)

        except Exception as e:
            state.mark_failed(f"Unexpected dry-run failure: {e}")
            self.reporter.write_report(state)
            raise

        return state

    def run_migration(
        self,
        db: Session,
        mongo_db: Database,
        migration_id: Optional[str] = None,
        allow_unsafe_engine: bool = False,
    ) -> MigrationState:
        """Execute live controlled data migration from PostgreSQL to MongoDB with deterministic upsert."""
        # Safety Guard 1: Verify PostgreSQL remains configured as default/source of truth
        if settings.PERSISTENCE_ENGINE != "postgresql" and not allow_unsafe_engine:
            raise RuntimeError(
                f"Safety check rejected migration: PERSISTENCE_ENGINE is '{settings.PERSISTENCE_ENGINE}'. "
                "PostgreSQL must remain the active primary source of truth during migration."
            )

        # Safety Guard 2: Verify MongoDB connection is reachable
        try:
            mongo_db.command("ping")
        except Exception as conn_err:
            raise RuntimeError(f"Safety check rejected migration: MongoDB destination unreachable: {conn_err}")

        mig_id = migration_id or generate_migration_id()
        state = MigrationState(
            migration_id=mig_id,
            mode="migrate",
            source_database="postgresql",
            destination_database="mongodb",
        )

        try:
            verifier = MigrationVerifier(db, mongo_db)
            state.destination_counts_before = verifier.get_mongodb_counts()

            # Step 1: Extraction
            extractor = PostgreSQLExtractor(db)
            state.source_counts = extractor.get_source_counts()

            raw_entities = {
                "users": extractor.extract_users(),
                "user_settings": extractor.extract_user_settings(),
                "clients": extractor.extract_clients(),
                "workflows": extractor.extract_workflows(),
                "task_templates": extractor.extract_task_templates(),
                "recurring_tasks": extractor.extract_recurring_tasks(),
                "tasks": extractor.extract_tasks(),
                "task_history": extractor.extract_task_histories(),
                "recurring_task_executions": extractor.extract_recurring_task_executions(),
                "notifications": extractor.extract_notifications(),
                "events": extractor.extract_events(),
                "refresh_tokens": extractor.extract_refresh_tokens(),
            }

            # Step 2: Relationship Validation
            rel_errors = MigrationValidator.validate_relationships(raw_entities)
            state.relationship_errors.extend(rel_errors)
            if rel_errors:
                state.mark_failed(
                    f"Migration aborted before writing: {len(rel_errors)} broken foreign key references found."
                )
                self.reporter.write_report(state)
                return state

            # Step 3: Transformation
            transformed: Dict[str, List[Any]] = {}
            for u in raw_entities["users"]:
                transformed.setdefault("users", []).append(EntityTransformer.transform_user(u))
            for s in raw_entities["user_settings"]:
                transformed.setdefault("user_settings", []).append(
                    EntityTransformer.transform_user_settings(s)
                )
            for c in raw_entities["clients"]:
                transformed.setdefault("clients", []).append(EntityTransformer.transform_client(c))
            for w in raw_entities["workflows"]:
                transformed.setdefault("workflows", []).append(EntityTransformer.transform_workflow(w))
            for tt in raw_entities["task_templates"]:
                transformed.setdefault("task_templates", []).append(
                    EntityTransformer.transform_task_template(tt)
                )
            for rt in raw_entities["recurring_tasks"]:
                transformed.setdefault("recurring_tasks", []).append(
                    EntityTransformer.transform_recurring_task(rt)
                )
            for t in raw_entities["tasks"]:
                transformed.setdefault("tasks", []).append(EntityTransformer.transform_task(t))
            for h in raw_entities["task_history"]:
                transformed.setdefault("task_history", []).append(
                    EntityTransformer.transform_task_history(h)
                )
            for re in raw_entities["recurring_task_executions"]:
                transformed.setdefault("recurring_task_executions", []).append(
                    EntityTransformer.transform_recurring_task_execution(re)
                )
            for n in raw_entities["notifications"]:
                transformed.setdefault("notifications", []).append(
                    EntityTransformer.transform_notification(n)
                )
            for ev in raw_entities["events"]:
                transformed.setdefault("events", []).append(EntityTransformer.transform_event(ev))
            for tok in raw_entities["refresh_tokens"]:
                transformed.setdefault("refresh_tokens", []).append(
                    EntityTransformer.transform_refresh_token(tok)
                )

            # Step 4: Loading into MongoDB
            loader = MongoDBLoader(mongo_db, migration_id=mig_id)
            state = loader.load_all(transformed, state)

            # Step 5: Post-migration verification
            state.destination_counts_after = verifier.get_mongodb_counts()
            count_comparison = verifier.verify_counts(state.source_counts)
            task_distributions = verifier.verify_task_distributions()
            checksum_mismatches = verifier.verify_checksums(transformed)
            state.checksum_mismatches.extend(checksum_mismatches)

            # Determine final status
            all_counts_match = all(cmp["match"] for cmp in count_comparison.values())
            no_checksum_errors = len(checksum_mismatches) == 0
            no_load_errors = sum(state.failed.values()) == 0

            if all_counts_match and no_checksum_errors and no_load_errors:
                state.mark_completed()
            else:
                state.mark_failed(
                    f"Migration completed with discrepancies: counts_match={all_counts_match}, "
                    f"checksum_errors={len(checksum_mismatches)}, load_errors={sum(state.failed.values())}"
                )

            self.reporter.write_report(state, count_comparison, task_distributions)

        except Exception as e:
            state.mark_failed(f"Migration execution error: {e}")
            self.reporter.write_report(state)
            raise

        return state

    def run_rollback(self, mongo_db: Database, migration_id: str) -> Dict[str, int]:
        """Roll back all MongoDB documents tagged with the specified migration ID."""
        deleted_counts = MigrationRollback.rollback(mongo_db, migration_id)
        logger.info(f"Migration rollback completed for {migration_id}: {deleted_counts}")
        return deleted_counts
