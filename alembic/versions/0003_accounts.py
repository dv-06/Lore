"""Add user accounts, invitations, session ownership, and document ownership.

Revision ID: 0003_accounts
Revises: 0002_pairing_attempts
Create Date: 2026-11-03

No accounts are created and no documents are assigned by this migration.
Existing pairing sessions are marked `auth_method = 'pairing'` and remain
unowned; a document's `owner_user_id` stays NULL until the explicit Phase
2.1B ownership step.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect

revision: str = "0003_accounts"
down_revision: Union[str, None] = "0002_pairing_attempts"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

IDENTITY_CHECK = (
    "(auth_method = 'pairing' AND user_id IS NULL) "
    "OR (auth_method = 'password' AND user_id IS NOT NULL)"
)


def _tables(bind) -> set[str]:
    return set(inspect(bind).get_table_names())


def _columns(bind, table: str) -> set[str]:
    return {column["name"] for column in inspect(bind).get_columns(table)}


def _create_users() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("email", sa.String(254), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column(
            "role", sa.String(16), nullable=False, server_default="user"
        ),
        sa.Column(
            "status", sa.String(16), nullable=False, server_default="active"
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_login_at", sa.DateTime(timezone=True)),
        sa.UniqueConstraint("email", name="uq_users_email"),
        sa.CheckConstraint("role IN ('owner', 'user')", name="ck_users_role"),
        sa.CheckConstraint(
            "status IN ('active', 'disabled')", name="ck_users_status"
        ),
    )
    # SQLite and PostgreSQL both support partial unique indexes. This is the
    # database-level guarantee that exactly one owner can exist.
    op.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_users_single_owner "
        "ON users (role) WHERE role = 'owner'"
    )


def _create_invitations() -> None:
    op.create_table(
        "invitations",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("token_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("email", sa.String(254), nullable=False),
        sa.Column(
            "created_by",
            sa.String(36),
            sa.ForeignKey("users.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True)),
        sa.Column(
            "used_by",
            sa.String(36),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
        ),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
    )
    op.create_index(
        "ix_invitations_email", "invitations", ["email"], if_not_exists=True
    )
    op.create_index(
        "ix_invitations_expires_at",
        "invitations",
        ["expires_at"],
        if_not_exists=True,
    )


def _alter_auth_sessions(bind) -> None:
    columns = _columns(bind, "auth_sessions")
    missing_user_id = "user_id" not in columns
    missing_method = "auth_method" not in columns
    if missing_user_id or missing_method:
        if bind.dialect.name == "sqlite":
            with op.batch_alter_table("auth_sessions") as batch:
                if missing_user_id:
                    batch.add_column(sa.Column("user_id", sa.String(36)))
                if missing_method:
                    batch.add_column(
                        sa.Column(
                            "auth_method",
                            sa.String(16),
                            nullable=False,
                            server_default="pairing",
                        )
                    )
                batch.create_foreign_key(
                    "fk_auth_sessions_user_id_users",
                    "users",
                    ["user_id"],
                    ["id"],
                    ondelete="CASCADE",
                )
                batch.create_check_constraint(
                    "ck_auth_sessions_auth_method",
                    "auth_method IN ('pairing', 'password')",
                )
                batch.create_check_constraint(
                    "ck_auth_sessions_identity_consistency", IDENTITY_CHECK
                )
        else:
            if missing_user_id:
                op.add_column(
                    "auth_sessions", sa.Column("user_id", sa.String(36))
                )
            if missing_method:
                op.add_column(
                    "auth_sessions",
                    sa.Column(
                        "auth_method",
                        sa.String(16),
                        nullable=False,
                        server_default="pairing",
                    ),
                )
            op.create_foreign_key(
                "fk_auth_sessions_user_id_users",
                "auth_sessions",
                "users",
                ["user_id"],
                ["id"],
                ondelete="CASCADE",
            )
            op.create_check_constraint(
                "ck_auth_sessions_auth_method",
                "auth_sessions",
                "auth_method IN ('pairing', 'password')",
            )
            op.create_check_constraint(
                "ck_auth_sessions_identity_consistency",
                "auth_sessions",
                IDENTITY_CHECK,
            )
    op.create_index(
        "ix_auth_sessions_user_id",
        "auth_sessions",
        ["user_id"],
        if_not_exists=True,
    )


def _alter_documents(bind) -> None:
    if "owner_user_id" not in _columns(bind, "documents"):
        op.add_column("documents", sa.Column("owner_user_id", sa.String(36)))
    op.create_index(
        "ix_documents_owner_user_id",
        "documents",
        ["owner_user_id"],
        if_not_exists=True,
    )
    if bind.dialect.name == "sqlite":
        # SQLite cannot add a foreign key without rebuilding the table. The
        # documents table is referenced by relationships, so a rebuild here
        # would risk touching existing data. Ownership is enforced by the
        # application and later migrations on SQLite; PostgreSQL gets the FK.
        return
    foreign_keys = {
        fk["name"] for fk in inspect(bind).get_foreign_keys("documents")
    }
    if "fk_documents_owner_user_id_users" not in foreign_keys:
        op.create_foreign_key(
            "fk_documents_owner_user_id_users",
            "documents",
            "users",
            ["owner_user_id"],
            ["id"],
            ondelete="RESTRICT",
        )


def upgrade() -> None:
    bind = op.get_bind()
    existing = _tables(bind)
    if "users" not in existing:
        _create_users()
    if "invitations" not in existing:
        _create_invitations()
    _alter_auth_sessions(bind)
    _alter_documents(bind)


def downgrade() -> None:
    bind = op.get_bind()
    existing = _tables(bind)

    if "documents" in existing:
        op.drop_index(
            "ix_documents_owner_user_id",
            table_name="documents",
            if_exists=True,
        )
        if bind.dialect.name == "sqlite":
            # Plain DROP COLUMN avoids rebuilding a table that relationships
            # reference. SQLite 3.35+ supports it; Python 3.12+ bundles newer.
            op.execute("ALTER TABLE documents DROP COLUMN owner_user_id")
        else:
            foreign_keys = {
                fk["name"]
                for fk in inspect(bind).get_foreign_keys("documents")
            }
            if "fk_documents_owner_user_id_users" in foreign_keys:
                op.drop_constraint(
                    "fk_documents_owner_user_id_users",
                    "documents",
                    type_="foreignkey",
                )
            op.drop_column("documents", "owner_user_id")

    if "auth_sessions" in existing:
        op.drop_index(
            "ix_auth_sessions_user_id",
            table_name="auth_sessions",
            if_exists=True,
        )
        if bind.dialect.name == "sqlite":
            with op.batch_alter_table("auth_sessions") as batch:
                batch.drop_constraint(
                    "ck_auth_sessions_identity_consistency", type_="check"
                )
                batch.drop_constraint(
                    "ck_auth_sessions_auth_method", type_="check"
                )
                batch.drop_constraint(
                    "fk_auth_sessions_user_id_users", type_="foreignkey"
                )
                batch.drop_column("auth_method")
                batch.drop_column("user_id")
        else:
            op.drop_constraint(
                "ck_auth_sessions_identity_consistency",
                "auth_sessions",
                type_="check",
            )
            op.drop_constraint(
                "ck_auth_sessions_auth_method", "auth_sessions", type_="check"
            )
            op.drop_constraint(
                "fk_auth_sessions_user_id_users",
                "auth_sessions",
                type_="foreignkey",
            )
            op.drop_column("auth_sessions", "auth_method")
            op.drop_column("auth_sessions", "user_id")

    if "invitations" in existing:
        op.drop_table("invitations")
    if "users" in existing:
        op.drop_table("users")
