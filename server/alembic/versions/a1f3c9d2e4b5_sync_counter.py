"""sync_counter: atomic server_seq allocator

Revision ID: a1f3c9d2e4b5
Revises: dbdde1c2d798
"""

import sqlalchemy as sa

from alembic import op

revision = "a1f3c9d2e4b5"
down_revision = "dbdde1c2d798"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "sync_counter",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("value", sa.Integer(), nullable=False),
    )
    op.execute("INSERT INTO sync_counter (id, value) SELECT 1, COALESCE(MAX(server_seq), 0) FROM record")


def downgrade() -> None:
    op.drop_table("sync_counter")
