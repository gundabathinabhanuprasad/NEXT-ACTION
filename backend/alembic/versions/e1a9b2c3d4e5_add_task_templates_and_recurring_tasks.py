"""Add task templates and recurring tasks

Revision ID: e1a9b2c3d4e5
Revises: d7a8f3b4e5c6
Create Date: 2026-09-29 07:15:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'e1a9b2c3d4e5'
down_revision: Union[str, None] = 'd7a8f3b4e5c6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Create recurrence_type enum safely
    recurrence_type_enum = postgresql.ENUM('DAILY', 'WEEKLY', 'MONTHLY', 'CUSTOM_INTERVAL', name='recurrence_type', create_type=False)
    recurrence_type_ddl = postgresql.ENUM('DAILY', 'WEEKLY', 'MONTHLY', 'CUSTOM_INTERVAL', name='recurrence_type')
    recurrence_type_ddl.create(op.get_bind(), checkfirst=True)

    # Reference existing task_priority enum
    task_priority_enum = postgresql.ENUM('LOW', 'MEDIUM', 'HIGH', 'URGENT', name='task_priority', create_type=False)

    # 2. Create task_templates table
    op.create_table(
        'task_templates',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('subject_line', sa.String(length=500), nullable=True),
        sa.Column('workflow_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('workflows.id', ondelete='SET NULL'), nullable=True),
        sa.Column('client_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('clients.id', ondelete='SET NULL'), nullable=True),
        sa.Column('assigned_user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('priority', task_priority_enum, nullable=False, server_default='MEDIUM'),
        sa.Column('max_attempts', sa.Integer(), nullable=False, server_default='2'),
        sa.Column('default_due_offset_days', sa.Integer(), nullable=True),
        sa.Column('default_next_action_offset_days', sa.Integer(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('created_by_user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    )
    op.create_index(op.f('ix_task_templates_name'), 'task_templates', ['name'], unique=False)
    op.create_index(op.f('ix_task_templates_workflow_id'), 'task_templates', ['workflow_id'], unique=False)
    op.create_index(op.f('ix_task_templates_client_id'), 'task_templates', ['client_id'], unique=False)
    op.create_index(op.f('ix_task_templates_assigned_user_id'), 'task_templates', ['assigned_user_id'], unique=False)
    op.create_index(op.f('ix_task_templates_priority'), 'task_templates', ['priority'], unique=False)
    op.create_index(op.f('ix_task_templates_is_active'), 'task_templates', ['is_active'], unique=False)
    op.create_index(op.f('ix_task_templates_created_by_user_id'), 'task_templates', ['created_by_user_id'], unique=False)

    # 3. Create recurring_tasks table
    op.create_table(
        'recurring_tasks',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('template_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('task_templates.id', ondelete='SET NULL'), nullable=True),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('subject_line', sa.String(length=500), nullable=True),
        sa.Column('workflow_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('workflows.id', ondelete='SET NULL'), nullable=True),
        sa.Column('client_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('clients.id', ondelete='SET NULL'), nullable=True),
        sa.Column('assigned_user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('priority', task_priority_enum, nullable=False, server_default='MEDIUM'),
        sa.Column('max_attempts', sa.Integer(), nullable=False, server_default='2'),
        sa.Column('due_offset_days', sa.Integer(), nullable=True),
        sa.Column('next_action_offset_days', sa.Integer(), nullable=True),
        sa.Column('recurrence_type', recurrence_type_enum, nullable=False, server_default='DAILY'),
        sa.Column('interval', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('day_of_week', sa.Integer(), nullable=True),
        sa.Column('day_of_month', sa.Integer(), nullable=True),
        sa.Column('start_date', sa.DateTime(timezone=True), nullable=False),
        sa.Column('end_date', sa.DateTime(timezone=True), nullable=True),
        sa.Column('next_run_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('last_run_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('created_by_user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    )
    op.create_index(op.f('ix_recurring_tasks_template_id'), 'recurring_tasks', ['template_id'], unique=False)
    op.create_index(op.f('ix_recurring_tasks_name'), 'recurring_tasks', ['name'], unique=False)
    op.create_index(op.f('ix_recurring_tasks_workflow_id'), 'recurring_tasks', ['workflow_id'], unique=False)
    op.create_index(op.f('ix_recurring_tasks_client_id'), 'recurring_tasks', ['client_id'], unique=False)
    op.create_index(op.f('ix_recurring_tasks_assigned_user_id'), 'recurring_tasks', ['assigned_user_id'], unique=False)
    op.create_index(op.f('ix_recurring_tasks_priority'), 'recurring_tasks', ['priority'], unique=False)
    op.create_index(op.f('ix_recurring_tasks_recurrence_type'), 'recurring_tasks', ['recurrence_type'], unique=False)
    op.create_index(op.f('ix_recurring_tasks_next_run_at'), 'recurring_tasks', ['next_run_at'], unique=False)
    op.create_index(op.f('ix_recurring_tasks_is_active'), 'recurring_tasks', ['is_active'], unique=False)
    op.create_index(op.f('ix_recurring_tasks_created_by_user_id'), 'recurring_tasks', ['created_by_user_id'], unique=False)

    # 4. Create recurring_task_executions table
    op.create_table(
        'recurring_task_executions',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('recurring_task_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('recurring_tasks.id', ondelete='CASCADE'), nullable=False),
        sa.Column('scheduled_for', sa.DateTime(timezone=True), nullable=False),
        sa.Column('task_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('tasks.id', ondelete='SET NULL'), nullable=True),
        sa.Column('status', sa.String(length=50), nullable=False, server_default='success'),
        sa.Column('executed_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.UniqueConstraint('recurring_task_id', 'scheduled_for', name='uq_recurring_execution_schedule'),
    )
    op.create_index(op.f('ix_recurring_task_executions_recurring_task_id'), 'recurring_task_executions', ['recurring_task_id'], unique=False)
    op.create_index(op.f('ix_recurring_task_executions_scheduled_for'), 'recurring_task_executions', ['scheduled_for'], unique=False)
    op.create_index(op.f('ix_recurring_task_executions_task_id'), 'recurring_task_executions', ['task_id'], unique=False)

    # 5. Add template_id and recurring_task_id to tasks table
    op.add_column('tasks', sa.Column('template_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('task_templates.id', ondelete='SET NULL'), nullable=True))
    op.add_column('tasks', sa.Column('recurring_task_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('recurring_tasks.id', ondelete='SET NULL'), nullable=True))
    op.create_index(op.f('ix_tasks_template_id'), 'tasks', ['template_id'], unique=False)
    op.create_index(op.f('ix_tasks_recurring_task_id'), 'tasks', ['recurring_task_id'], unique=False)


def downgrade() -> None:
    # 1. Remove columns from tasks
    op.drop_index(op.f('ix_tasks_recurring_task_id'), table_name='tasks')
    op.drop_index(op.f('ix_tasks_template_id'), table_name='tasks')
    op.drop_column('tasks', 'recurring_task_id')
    op.drop_column('tasks', 'template_id')

    # 2. Drop recurring_task_executions
    op.drop_index(op.f('ix_recurring_task_executions_task_id'), table_name='recurring_task_executions')
    op.drop_index(op.f('ix_recurring_task_executions_scheduled_for'), table_name='recurring_task_executions')
    op.drop_index(op.f('ix_recurring_task_executions_recurring_task_id'), table_name='recurring_task_executions')
    op.drop_table('recurring_task_executions')

    # 3. Drop recurring_tasks
    op.drop_index(op.f('ix_recurring_tasks_created_by_user_id'), table_name='recurring_tasks')
    op.drop_index(op.f('ix_recurring_tasks_is_active'), table_name='recurring_tasks')
    op.drop_index(op.f('ix_recurring_tasks_next_run_at'), table_name='recurring_tasks')
    op.drop_index(op.f('ix_recurring_tasks_recurrence_type'), table_name='recurring_tasks')
    op.drop_index(op.f('ix_recurring_tasks_priority'), table_name='recurring_tasks')
    op.drop_index(op.f('ix_recurring_tasks_assigned_user_id'), table_name='recurring_tasks')
    op.drop_index(op.f('ix_recurring_tasks_client_id'), table_name='recurring_tasks')
    op.drop_index(op.f('ix_recurring_tasks_workflow_id'), table_name='recurring_tasks')
    op.drop_index(op.f('ix_recurring_tasks_name'), table_name='recurring_tasks')
    op.drop_index(op.f('ix_recurring_tasks_template_id'), table_name='recurring_tasks')
    op.drop_table('recurring_tasks')

    # 4. Drop task_templates
    op.drop_index(op.f('ix_task_templates_created_by_user_id'), table_name='task_templates')
    op.drop_index(op.f('ix_task_templates_is_active'), table_name='task_templates')
    op.drop_index(op.f('ix_task_templates_priority'), table_name='task_templates')
    op.drop_index(op.f('ix_task_templates_assigned_user_id'), table_name='task_templates')
    op.drop_index(op.f('ix_task_templates_client_id'), table_name='task_templates')
    op.drop_index(op.f('ix_task_templates_workflow_id'), table_name='task_templates')
    op.drop_index(op.f('ix_task_templates_name'), table_name='task_templates')
    op.drop_table('task_templates')

    # 5. Drop recurrence_type enum
    recurrence_type_enum = postgresql.ENUM('DAILY', 'WEEKLY', 'MONTHLY', 'CUSTOM_INTERVAL', name='recurrence_type')
    recurrence_type_enum.drop(op.get_bind(), checkfirst=True)
