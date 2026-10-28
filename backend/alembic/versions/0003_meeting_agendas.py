"""meeting agendas, with the AI suggestion each one started from

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-15
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "meeting_agendas",
        sa.Column(
            "meeting_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("meetings.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("items", postgresql.JSONB(), nullable=False, server_default="[]"),
        sa.Column("action_items", postgresql.JSONB(), nullable=False, server_default="[]"),
        sa.Column("ai_suggestion", postgresql.JSONB(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )


def downgrade() -> None:
    op.drop_table("meeting_agendas")
