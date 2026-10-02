"""Validation layer: Enforces referential integrity and schema invariants before writing."""

from typing import Any, Dict, List, Set
from app.migration.state import RelationshipError


class MigrationValidator:
    """Validates relational references across extracted PostgreSQL entities before MongoDB loading."""

    @staticmethod
    def validate_relationships(extracted_data: Dict[str, List[Any]]) -> List[RelationshipError]:
        """Validate foreign key relationships across all extracted entities.

        Returns a list of RelationshipError objects for any dangling or missing references.
        """
        errors: List[RelationshipError] = []

        # Index primary key sets as string UUIDs
        user_ids: Set[str] = {str(u.id) for u in extracted_data.get("users", [])}
        client_ids: Set[str] = {str(c.id) for c in extracted_data.get("clients", [])}
        workflow_ids: Set[str] = {str(w.id) for w in extracted_data.get("workflows", [])}
        template_ids: Set[str] = {str(t.id) for t in extracted_data.get("task_templates", [])}
        recurring_task_ids: Set[str] = {
            str(r.id) for r in extracted_data.get("recurring_tasks", [])
        }
        task_ids: Set[str] = {str(t.id) for t in extracted_data.get("tasks", [])}

        # 1. UserSettings -> User
        for s in extracted_data.get("user_settings", []):
            uid = str(s.user_id)
            if uid not in user_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="user_settings",
                        parent_id=str(s.id),
                        reference_field="user_id",
                        referenced_entity="users",
                        broken_id=uid,
                        message=f"UserSettings {s.id} references non-existent user {uid}",
                    )
                )

        # 2. TaskTemplate references
        for t in extracted_data.get("task_templates", []):
            tid = str(t.id)
            if t.workflow_id and str(t.workflow_id) not in workflow_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="task_templates",
                        parent_id=tid,
                        reference_field="workflow_id",
                        referenced_entity="workflows",
                        broken_id=str(t.workflow_id),
                        message=f"TaskTemplate {tid} references non-existent workflow {t.workflow_id}",
                    )
                )
            if t.client_id and str(t.client_id) not in client_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="task_templates",
                        parent_id=tid,
                        reference_field="client_id",
                        referenced_entity="clients",
                        broken_id=str(t.client_id),
                        message=f"TaskTemplate {tid} references non-existent client {t.client_id}",
                    )
                )
            if t.assigned_user_id and str(t.assigned_user_id) not in user_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="task_templates",
                        parent_id=tid,
                        reference_field="assigned_user_id",
                        referenced_entity="users",
                        broken_id=str(t.assigned_user_id),
                        message=f"TaskTemplate {tid} references non-existent assigned user {t.assigned_user_id}",
                    )
                )
            if t.created_by_user_id and str(t.created_by_user_id) not in user_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="task_templates",
                        parent_id=tid,
                        reference_field="created_by_user_id",
                        referenced_entity="users",
                        broken_id=str(t.created_by_user_id),
                        message=f"TaskTemplate {tid} references non-existent creator user {t.created_by_user_id}",
                    )
                )

        # 3. RecurringTask references
        for r in extracted_data.get("recurring_tasks", []):
            rid = str(r.id)
            if r.template_id and str(r.template_id) not in template_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="recurring_tasks",
                        parent_id=rid,
                        reference_field="template_id",
                        referenced_entity="task_templates",
                        broken_id=str(r.template_id),
                        message=f"RecurringTask {rid} references non-existent template {r.template_id}",
                    )
                )
            if r.workflow_id and str(r.workflow_id) not in workflow_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="recurring_tasks",
                        parent_id=rid,
                        reference_field="workflow_id",
                        referenced_entity="workflows",
                        broken_id=str(r.workflow_id),
                        message=f"RecurringTask {rid} references non-existent workflow {r.workflow_id}",
                    )
                )
            if r.client_id and str(r.client_id) not in client_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="recurring_tasks",
                        parent_id=rid,
                        reference_field="client_id",
                        referenced_entity="clients",
                        broken_id=str(r.client_id),
                        message=f"RecurringTask {rid} references non-existent client {r.client_id}",
                    )
                )
            if r.assigned_user_id and str(r.assigned_user_id) not in user_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="recurring_tasks",
                        parent_id=rid,
                        reference_field="assigned_user_id",
                        referenced_entity="users",
                        broken_id=str(r.assigned_user_id),
                        message=f"RecurringTask {rid} references non-existent user {r.assigned_user_id}",
                    )
                )
            if r.created_by_user_id and str(r.created_by_user_id) not in user_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="recurring_tasks",
                        parent_id=rid,
                        reference_field="created_by_user_id",
                        referenced_entity="users",
                        broken_id=str(r.created_by_user_id),
                        message=f"RecurringTask {rid} references non-existent creator {r.created_by_user_id}",
                    )
                )

        # 4. Task references
        for task in extracted_data.get("tasks", []):
            task_id = str(task.id)
            if task.workflow_id and str(task.workflow_id) not in workflow_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="tasks",
                        parent_id=task_id,
                        reference_field="workflow_id",
                        referenced_entity="workflows",
                        broken_id=str(task.workflow_id),
                        message=f"Task {task_id} references non-existent workflow {task.workflow_id}",
                    )
                )
            if task.client_id and str(task.client_id) not in client_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="tasks",
                        parent_id=task_id,
                        reference_field="client_id",
                        referenced_entity="clients",
                        broken_id=str(task.client_id),
                        message=f"Task {task_id} references non-existent client {task.client_id}",
                    )
                )
            if task.assigned_user_id and str(task.assigned_user_id) not in user_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="tasks",
                        parent_id=task_id,
                        reference_field="assigned_user_id",
                        referenced_entity="users",
                        broken_id=str(task.assigned_user_id),
                        message=f"Task {task_id} references non-existent assigned user {task.assigned_user_id}",
                    )
                )
            if task.template_id and str(task.template_id) not in template_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="tasks",
                        parent_id=task_id,
                        reference_field="template_id",
                        referenced_entity="task_templates",
                        broken_id=str(task.template_id),
                        message=f"Task {task_id} references non-existent template {task.template_id}",
                    )
                )
            if task.recurring_task_id and str(task.recurring_task_id) not in recurring_task_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="tasks",
                        parent_id=task_id,
                        reference_field="recurring_task_id",
                        referenced_entity="recurring_tasks",
                        broken_id=str(task.recurring_task_id),
                        message=f"Task {task_id} references non-existent recurring task {task.recurring_task_id}",
                    )
                )

        # 5. TaskHistory -> Task / User
        for h in extracted_data.get("task_history", []):
            hid = str(h.id)
            if h.task_id and str(h.task_id) not in task_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="task_history",
                        parent_id=hid,
                        reference_field="task_id",
                        referenced_entity="tasks",
                        broken_id=str(h.task_id),
                        message=f"TaskHistory {hid} references non-existent task {h.task_id}",
                    )
                )
            if h.created_by_user_id and str(h.created_by_user_id) not in user_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="task_history",
                        parent_id=hid,
                        reference_field="created_by_user_id",
                        referenced_entity="users",
                        broken_id=str(h.created_by_user_id),
                        message=f"TaskHistory {hid} references non-existent user {h.created_by_user_id}",
                    )
                )

        # 6. RecurringTaskExecution -> RecurringTask / Task
        for e in extracted_data.get("recurring_task_executions", []):
            eid = str(e.id)
            rid = str(e.recurring_task_id)
            if rid not in recurring_task_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="recurring_task_executions",
                        parent_id=eid,
                        reference_field="recurring_task_id",
                        referenced_entity="recurring_tasks",
                        broken_id=rid,
                        message=f"Execution {eid} references non-existent recurring task {rid}",
                    )
                )
            if e.task_id and str(e.task_id) not in task_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="recurring_task_executions",
                        parent_id=eid,
                        reference_field="task_id",
                        referenced_entity="tasks",
                        broken_id=str(e.task_id),
                        message=f"Execution {eid} references non-existent task {e.task_id}",
                    )
                )

        # 7. Notification -> User / Task
        for n in extracted_data.get("notifications", []):
            nid = str(n.id)
            uid = str(n.user_id)
            if uid not in user_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="notifications",
                        parent_id=nid,
                        reference_field="user_id",
                        referenced_entity="users",
                        broken_id=uid,
                        message=f"Notification {nid} references non-existent user {uid}",
                    )
                )
            if n.task_id and str(n.task_id) not in task_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="notifications",
                        parent_id=nid,
                        reference_field="task_id",
                        referenced_entity="tasks",
                        broken_id=str(n.task_id),
                        message=f"Notification {nid} references non-existent task {n.task_id}",
                    )
                )

        # 8. Event -> Task / Client
        for ev in extracted_data.get("events", []):
            ev_id = str(ev.id)
            if ev.task_id and str(ev.task_id) not in task_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="events",
                        parent_id=ev_id,
                        reference_field="task_id",
                        referenced_entity="tasks",
                        broken_id=str(ev.task_id),
                        message=f"Event {ev_id} references non-existent task {ev.task_id}",
                    )
                )
            if ev.client_id and str(ev.client_id) not in client_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="events",
                        parent_id=ev_id,
                        reference_field="client_id",
                        referenced_entity="clients",
                        broken_id=str(ev.client_id),
                        message=f"Event {ev_id} references non-existent client {ev.client_id}",
                    )
                )

        # 9. RefreshToken -> User
        for rt in extracted_data.get("refresh_tokens", []):
            rt_id = str(rt.id)
            uid = str(rt.user_id)
            if uid not in user_ids:
                errors.append(
                    RelationshipError(
                        parent_entity="refresh_tokens",
                        parent_id=rt_id,
                        reference_field="user_id",
                        referenced_entity="users",
                        broken_id=uid,
                        message=f"RefreshToken {rt_id} references non-existent user {uid}",
                    )
                )

        return errors
