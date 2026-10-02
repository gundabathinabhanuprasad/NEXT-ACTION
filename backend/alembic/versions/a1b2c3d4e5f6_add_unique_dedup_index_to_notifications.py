"""add_unique_dedup_index_to_notifications

Revision ID: a1b2c3d4e5f6
Revises: f2b8c9d0e1f2
Create Date: 2026-09-29 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'f2b8c9d0e1f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add database-level partial unique index to guarantee atomic notification deduplication."""
    op.create_index(
        'uq_notifications_user_dedup',
        'notifications',
        ['user_id', 'dedup_key'],
        unique=True,
        postgresql_where=sa.text('dedup_key IS NOT NULL'),
    )


def downgrade() -> None:
    """Drop database-level partial unique index."""
    op.drop_index(
        'uq_notifications_user_dedup',
        table_name='notifications',
    )
