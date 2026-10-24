"""session.expires_at: bearer tokens get a hard lifetime

Revision ID: c7e2b8f1a9d3
Revises: a1f3c9d2e4b5
"""

from datetime import UTC, datetime, timedelta

import sqlalchemy as sa

from alembic import op

revision = "c7e2b8f1a9d3"
down_revision = "a1f3c9d2e4b5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("session", sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True))
    # Existing tokens get one fresh 365-day window from deploy time, then follow the normal rules.
    session = sa.table("session", sa.column("expires_at", sa.DateTime(timezone=True)))
    op.execute(session.update().values(expires_at=datetime.now(UTC) + timedelta(days=365)))
    with op.batch_alter_table("session") as batch:
        batch.alter_column("expires_at", existing_type=sa.DateTime(timezone=True), nullable=False)


def downgrade() -> None:
    with op.batch_alter_table("session") as batch:
        batch.drop_column("expires_at")
