"""preserve_task_history_on_task_delete

Revision ID: 74b3a4c2d28a
Revises: 2261f48e1766
Create Date: 2026-09-27 13:40:11.295844

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '74b3a4c2d28a'
down_revision: Union[str, Sequence[str], None] = '2261f48e1766'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column('task_histories', 'task_id',
               existing_type=sa.UUID(),
               nullable=True)
    op.drop_constraint('task_histories_task_id_fkey', 'task_histories', type_='foreignkey')
    op.create_foreign_key('task_histories_task_id_fkey', 'task_histories', 'tasks', ['task_id'], ['id'], ondelete='SET NULL')


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint('task_histories_task_id_fkey', 'task_histories', type_='foreignkey')
    op.create_foreign_key('task_histories_task_id_fkey', 'task_histories', 'tasks', ['task_id'], ['id'], ondelete='CASCADE')
    op.alter_column('task_histories', 'task_id',
               existing_type=sa.UUID(),
               nullable=False)

