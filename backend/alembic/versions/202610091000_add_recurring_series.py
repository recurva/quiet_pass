"""add recurring_series table and reservations.recurring_series_id

Revision ID: 202610091000
Revises: 202610081200
Create Date: 2026-10-09 10:00:00

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "202610091000"
down_revision: Union[str, None] = "202610081200"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "recurring_series",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("space_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("weekdays", postgresql.ARRAY(sa.Integer()), nullable=False),
        sa.Column("start_hour_utc", sa.Integer(), nullable=False),
        sa.Column("start_minute_utc", sa.Integer(), nullable=False),
        sa.Column("duration_minutes", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["space_id"], ["spaces.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_recurring_series_group_id", "recurring_series", ["group_id"])
    op.create_index("ix_recurring_series_space_id", "recurring_series", ["space_id"])
    op.create_index("ix_recurring_series_user_id", "recurring_series", ["user_id"])

    op.add_column(
        "reservations", sa.Column("recurring_series_id", postgresql.UUID(as_uuid=True), nullable=True)
    )
    op.create_index(
        "ix_reservations_recurring_series_id", "reservations", ["recurring_series_id"]
    )
    op.create_foreign_key(
        "reservations_recurring_series_id_fkey",
        "reservations",
        "recurring_series",
        ["recurring_series_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "reservations_recurring_series_id_fkey", "reservations", type_="foreignkey"
    )
    op.drop_index("ix_reservations_recurring_series_id", table_name="reservations")
    op.drop_column("reservations", "recurring_series_id")

    op.drop_index("ix_recurring_series_user_id", table_name="recurring_series")
    op.drop_index("ix_recurring_series_space_id", table_name="recurring_series")
    op.drop_index("ix_recurring_series_group_id", table_name="recurring_series")
    op.drop_table("recurring_series")
