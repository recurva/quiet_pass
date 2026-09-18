"""add firebase_uid to users

Revision ID: 202609161200
Revises: 202609160001
Create Date: 2026-09-16 12:00:00

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "202609161200"
down_revision: Union[str, None] = "202609160001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("firebase_uid", sa.String(length=128), nullable=False, server_default=""),
    )
    op.alter_column("users", "firebase_uid", server_default=None)
    op.create_index("ix_users_firebase_uid", "users", ["firebase_uid"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_users_firebase_uid", table_name="users")
    op.drop_column("users", "firebase_uid")
