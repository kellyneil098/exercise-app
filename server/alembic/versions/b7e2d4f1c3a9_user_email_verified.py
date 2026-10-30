"""user.email_verified: only verified emails may be used to link Apple identities

Revision ID: b7e2d4f1c3a9
Revises: a1f3c9d2e4b5
"""

import sqlalchemy as sa

from alembic import op

revision = "b7e2d4f1c3a9"
down_revision = "a1f3c9d2e4b5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Existing rows' provenance is unknown, so they start unverified; a later verified sign-in upgrades them.
    op.add_column("user", sa.Column("email_verified", sa.Boolean(), server_default=sa.false(), nullable=False))


def downgrade() -> None:
    op.drop_column("user", "email_verified")
