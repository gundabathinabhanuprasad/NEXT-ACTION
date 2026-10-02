"""create_user_settings_table

Revision ID: f2b8c9d0e1f2
Revises: e1a9b2c3d4e5
Create Date: 2026-09-29 09:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'f2b8c9d0e1f2'
down_revision: Union[str, None] = 'e1a9b2c3d4e5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'user_settings',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('display_name_override', sa.String(length=255), nullable=True),
        sa.Column('timezone', sa.String(length=100), server_default='UTC', nullable=False),
        sa.Column('date_format', sa.String(length=50), server_default='YYYY-MM-DD', nullable=False),
        sa.Column('time_format', sa.String(length=20), server_default='24h', nullable=False),
        sa.Column('first_day_of_week', sa.String(length=20), server_default='monday', nullable=False),
        sa.Column('theme', sa.String(length=20), server_default='system', nullable=False),
        sa.Column('compact_mode', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('default_task_priority', sa.String(length=20), server_default='medium', nullable=False),
        sa.Column('default_task_status_filter', sa.String(length=20), server_default='all', nullable=False),
        sa.Column('default_task_sort', sa.String(length=50), server_default='due_date', nullable=False),
        sa.Column('default_task_sort_order', sa.String(length=10), server_default='asc', nullable=False),
        sa.Column('default_max_attempts', sa.Integer(), server_default='3', nullable=False),
        sa.Column('default_page_size', sa.Integer(), server_default='20', nullable=False),
        sa.Column('default_dashboard_time_range', sa.String(length=50), server_default='last_7_days', nullable=False),
        sa.Column('default_report_date_range', sa.String(length=50), server_default='last_7_days', nullable=False),
        sa.Column('default_report_type', sa.String(length=50), server_default='task_summary', nullable=False),
        sa.Column('default_export_format', sa.String(length=20), server_default='csv', nullable=False),
        sa.Column('notify_task_assigned', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('notify_task_reassigned', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('notify_reminder_due', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('notify_follow_up_due', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('notify_next_action_due', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('notify_task_overdue', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('notify_attempt_limit_reached', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('notify_task_completed', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('notify_task_reopened', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id'),
    )
    op.create_index(op.f('ix_user_settings_user_id'), 'user_settings', ['user_id'], unique=True)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_user_settings_user_id'), table_name='user_settings')
    op.drop_table('user_settings')
