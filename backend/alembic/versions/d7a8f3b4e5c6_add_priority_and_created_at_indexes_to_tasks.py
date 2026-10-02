"""Add priority and created_at indexes to tasks table

Revision ID: d7a8f3b4e5c6
Revises: c5e4a8b79f12
Create Date: 2026-09-29 05:35:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd7a8f3b4e5c6'
down_revision: Union[str, None] = 'c5e4a8b79f12'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create indexes on tasks.priority and tasks.created_at for fast filtering and sorting
    op.create_index(op.f('ix_tasks_priority'), 'tasks', ['priority'], unique=False)
    op.create_index(op.f('ix_tasks_created_at'), 'tasks', ['created_at'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_tasks_created_at'), table_name='tasks')
    op.drop_index(op.f('ix_tasks_priority'), table_name='tasks')
