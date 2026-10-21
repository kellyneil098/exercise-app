from datetime import UTC, datetime

from sqlalchemy import func, select, text
from sqlalchemy.orm import Session as DbSession

from . import models, schemas

PULL_PAGE = 500


def allocate_seq(db: DbSession, n: int) -> int:
    """Reserve `n` strictly increasing sequence numbers atomically; returns the first one."""
    if n <= 0:
        return 0
    last = db.execute(
        text("UPDATE sync_counter SET value = value + :n WHERE id = 1 RETURNING value"), {"n": n}
    ).scalar()
    if last is None:  # fresh database (tests / create_all): seed the counter from existing rows
        start = db.scalar(select(func.max(models.Record.server_seq))) or 0
        db.add(models.SyncCounter(id=1, value=start + n))
        db.flush()
        last = start + n
    return last - n + 1


def resequence_owner(db: DbSession, owner_id: str) -> None:
    """Give every row of `owner_id` a fresh server_seq so viewers whose cursor is already past them see them."""
    rows = db.scalars(
        select(models.Record).where(models.Record.user_id == owner_id).order_by(models.Record.server_seq)
    ).all()
    seq = allocate_seq(db, len(rows))
    for r in rows:
        r.server_seq = seq
        seq += 1


def push(db: DbSession, user: models.User, records: list[schemas.RecordIn]) -> schemas.PushOut:
    """Last-writer-wins on `updated_at`. Every row is forced onto the authenticated user (§10)."""
    ids = [r.id for r in records]
    existing = {r.id: r for r in db.scalars(select(models.Record).where(models.Record.id.in_(ids)))} if ids else {}
    pending: list[tuple[schemas.RecordIn, models.Record | None, datetime]] = []
    for r in records:
        if r.table not in schemas.SYNC_TABLES or r.payload.get("userId", user.id) != user.id:
            continue  # unknown table, or payload claims another owner
        updated_at = r.updated_at if r.updated_at.tzinfo else r.updated_at.replace(tzinfo=UTC)
        cur = existing.get(r.id)
        if cur is not None:
            if cur.user_id != user.id:
                continue  # someone else's row; never overwrite
            cur_updated = cur.updated_at if cur.updated_at.tzinfo else cur.updated_at.replace(tzinfo=UTC)
            if cur_updated >= updated_at:
                continue
        pending.append((r, cur, updated_at))
    ignored = len(records) - len(pending)
    accepted = 0
    if not pending:
        return schemas.PushOut(accepted=0, ignored=ignored, cursor=db.scalar(select(models.SyncCounter.value)) or 0)
    seq = allocate_seq(db, len(pending))
    for r, cur, updated_at in pending:
        if cur is not None:
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
    return schemas.PullOut(
        records=out,
        cursor=rows[-1].server_seq if rows else since,
        has_more=has_more,
        visible_user_ids=visible_user_ids(db, user),
    )


def utcnow() -> datetime:
    return datetime.now(UTC)
