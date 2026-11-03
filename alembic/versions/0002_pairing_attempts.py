"""Add the persisted pairing-attempt counter.

Revision ID: 0002_pairing_attempts
Revises: 0001_baseline
Create Date: 2026-11-03

Phase 1.3 introduced this table through SQLAlchemy `create_all`. Older
databases may already contain it, so creation is conditional.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect

revision: str = "0002_pairing_attempts"
down_revision: Union[str, None] = "0001_baseline"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    if "pairing_attempts" in set(inspect(op.get_bind()).get_table_names()):
        return
    op.create_table(
        "pairing_attempts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("failed_count", sa.Integer(), nullable=False),
        sa.Column("lockout_count", sa.Integer(), nullable=False),
        sa.Column("last_failed_at", sa.DateTime(timezone=True)),
        sa.Column("locked_until", sa.DateTime(timezone=True)),
    )


def downgrade() -> None:
    if "pairing_attempts" in set(inspect(op.get_bind()).get_table_names()):
        op.drop_table("pairing_attempts")
