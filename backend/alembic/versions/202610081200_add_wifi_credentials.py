"""add wifi_credentials table

Revision ID: 202610081200
Revises: 202610081100
Create Date: 2026-10-08 12:00:00

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "202610081200"
down_revision: Union[str, None] = "202610081100"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "wifi_credentials",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False, unique=True),
        sa.Column("ssid", sa.String(length=100), nullable=False),
        sa.Column("password", sa.String(length=100), nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"], ondelete="CASCADE"),
    )


def downgrade() -> None:
    op.drop_table("wifi_credentials")
