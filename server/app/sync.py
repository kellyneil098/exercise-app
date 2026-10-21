from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session as DbSession

from . import models, schemas

PULL_PAGE = 500


def next_seq(db: DbSession) -> int:
    return (db.scalar(select(func.max(models.Record.server_seq))) or 0) + 1


def push(db: DbSession, user: models.User, records: list[schemas.RecordIn]) -> schemas.PushOut:
    """Last-writer-wins on `updated_at`. Every row is forced onto the authenticated user (§10)."""
    accepted = ignored = 0
    seq = next_seq(db)
    ids = [r.id for r in records]
    existing = {r.id: r for r in db.scalars(select(models.Record).where(models.Record.id.in_(ids)))} if ids else {}
    for r in records:
        if r.table not in schemas.SYNC_TABLES:
            ignored += 1
            continue
        updated_at = r.updated_at if r.updated_at.tzinfo else r.updated_at.replace(tzinfo=UTC)
        cur = existing.get(r.id)
        if cur is not None:
            if cur.user_id != user.id:
                ignored += 1  # someone else's row; never overwrite
                continue
            cur_updated = cur.updated_at if cur.updated_at.tzinfo else cur.updated_at.replace(tzinfo=UTC)
            if cur_updated >= updated_at:
                ignored += 1
                continue
            cur.payload = r.payload if r.op == "upsert" else {}
            cur.deleted = r.op == "delete"
            cur.updated_at = updated_at
            cur.server_seq = seq
        else:
            db.add(
                models.Record(
                    id=r.id,
                    user_id=user.id,
                    table_name=r.table,
                    payload=r.payload if r.op == "upsert" else {},
                    updated_at=updated_at,
                    deleted=r.op == "delete",
                    server_seq=seq,
                )
            )
        accepted += 1
        seq += 1
    db.commit()
    return schemas.PushOut(accepted=accepted, ignored=ignored, cursor=seq - 1)


def visible_user_ids(db: DbSession, user: models.User) -> list[str]:
    owners = db.scalars(select(models.Share.owner_id).where(models.Share.viewer_id == user.id)).all()
    return [user.id, *owners]


def pull(db: DbSession, user: models.User, since: int) -> schemas.PullOut:
    """Own rows plus rows of every owner who shares with this user, in server_seq order."""
    q = (
        select(models.Record)
        .where(models.Record.user_id.in_(visible_user_ids(db, user)), models.Record.server_seq > since)
        .order_by(models.Record.server_seq)
        .limit(PULL_PAGE + 1)
    )
    rows = db.scalars(q).all()
    has_more = len(rows) > PULL_PAGE
    rows = rows[:PULL_PAGE]
    out = [
        schemas.RecordOut(
            id=r.id,
            user_id=r.user_id,
            table=r.table_name,
            payload=r.payload,
            updated_at=r.updated_at if r.updated_at.tzinfo else r.updated_at.replace(tzinfo=UTC),
            deleted=r.deleted,
            seq=r.server_seq,
        )
        for r in rows
    ]
    return schemas.PullOut(records=out, cursor=rows[-1].server_seq if rows else since, has_more=has_more)


def utcnow() -> datetime:
    return datetime.now(UTC)
