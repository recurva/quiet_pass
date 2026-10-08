"""add dinner_headcounts table

Revision ID: 202610081000
Revises: 202609241300
Create Date: 2026-10-08 10:00:00

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "202610081000"
down_revision: Union[str, None] = "202609241300"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # create_type=False: created explicitly on the next line instead of
    # letting create_table's own DDL compiler also try to CREATE TYPE
    # implicitly for this column (its default behavior for a Postgres
    # ENUM) — doing both raises "type already exists" on the second one.
    dinner_status = postgresql.ENUM("home", "staying_out", name="dinner_status", create_type=False)
    dinner_status.create(op.get_bind(), checkfirst=True)

    op.create_table(
        "dinner_headcounts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("status", dinner_status, nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("group_id", "user_id", "day", name="uq_dinner_headcount_group_user_day"),
    )
    op.create_index("ix_dinner_headcounts_group_id", "dinner_headcounts", ["group_id"])
    op.create_index("ix_dinner_headcounts_user_id", "dinner_headcounts", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_dinner_headcounts_user_id", table_name="dinner_headcounts")
    op.drop_index("ix_dinner_headcounts_group_id", table_name="dinner_headcounts")
    op.drop_table("dinner_headcounts")
    postgresql.ENUM(name="dinner_status").drop(op.get_bind())
