"""add deleted_firebase_uids tombstone table

Revision ID: 202609241300
Revises: 202609180900
Create Date: 2026-09-24 13:00:00

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "202609241300"
down_revision: Union[str, None] = "202609180900"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "deleted_firebase_uids",
        sa.Column("firebase_uid", sa.String(length=128), primary_key=True),
        sa.Column(
            "deleted_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_table("deleted_firebase_uids")
