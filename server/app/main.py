from fastapi import Depends, FastAPI, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session as DbSession

from . import auth, models, schemas, sync
from .config import settings
from .db import get_db

app = FastAPI(title="workout-server", version="0.1.0", docs_url=None, redoc_url=None)


def user_out(u: models.User) -> schemas.UserOut:
    return schemas.UserOut(id=u.id, email=u.email, display_name=u.display_name)


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.post("/auth/apple", response_model=schemas.TokenOut)
def auth_apple(body: schemas.AppleLoginIn, db: DbSession = Depends(get_db)) -> schemas.TokenOut:
    claims = auth.verify_apple_identity_token(body.identity_token)
    sub = claims["sub"]
    email = claims.get("email")
    email_verified = claims.get("email_verified") in (True, "true")
    user = db.scalar(select(models.User).where(models.User.apple_sub == sub))
    if user is None and email and email_verified:
        # Pre-provisioned by email (dev login or admin), now linking Apple identity.
        user = db.scalar(select(models.User).where(models.User.email == email))
        if user is not None:
            user.apple_sub = sub
    if user is None:
        user = models.User(apple_sub=sub, email=email, display_name=(body.display_name or "")[:80])
        db.add(user)
        db.flush()
        auth.consume_invite(db, body.invite_code, user)
    elif body.display_name and not user.display_name:
        user.display_name = body.display_name[:80]
    db.commit()
    return schemas.TokenOut(token=auth.issue_token(db, user, body.device_name), user=user_out(user))


@app.post("/auth/dev", response_model=schemas.TokenOut)
def auth_dev(body: schemas.DevLoginIn, db: DbSession = Depends(get_db)) -> schemas.TokenOut:
    if not settings().dev_login_enabled:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    email = body.email.strip().lower()
    user = db.scalar(select(models.User).where(models.User.email == email))
    if user is None:
        user = models.User(email=email, display_name=(body.display_name or email.split("@")[0])[:80])
        db.add(user)
        db.flush()
        auth.consume_invite(db, body.invite_code, user)
    db.commit()
    return schemas.TokenOut(token=auth.issue_token(db, user, body.device_name), user=user_out(user))


@app.get("/me", response_model=schemas.UserOut)
def me(user: models.User = Depends(auth.current_user)) -> schemas.UserOut:
    return user_out(user)


@app.post("/invites", response_model=schemas.InviteOut, status_code=201)
def create_invite(
    body: schemas.InviteCreateIn, user: models.User = Depends(auth.current_user), db: DbSession = Depends(get_db)
) -> schemas.InviteOut:
    inv = auth.create_invite(db, user, body.grant_view_to_inviter, body.grant_view_of_inviter)
    return schemas.InviteOut(
        code=inv.code,
        expires_at=inv.expires_at,
        grant_view_to_inviter=inv.grant_view_to_inviter,
        grant_view_of_inviter=inv.grant_view_of_inviter,
    )


@app.get("/shares", response_model=schemas.SharesOut)
def shares(user: models.User = Depends(auth.current_user), db: DbSession = Depends(get_db)) -> schemas.SharesOut:
    owners = db.scalars(
        select(models.User)
        .join(models.Share, models.Share.owner_id == models.User.id)
        .where(models.Share.viewer_id == user.id)
    ).all()
    viewers = db.scalars(
        select(models.User)
        .join(models.Share, models.Share.viewer_id == models.User.id)
        .where(models.Share.owner_id == user.id)
    ).all()
    return schemas.SharesOut(i_can_view=[user_out(u) for u in owners], can_view_me=[user_out(u) for u in viewers])


@app.delete("/shares/{viewer_id}", status_code=204)
def revoke_share(
    viewer_id: str, user: models.User = Depends(auth.current_user), db: DbSession = Depends(get_db)
) -> None:
    share = db.scalar(select(models.Share).where(models.Share.owner_id == user.id, models.Share.viewer_id == viewer_id))
    if share is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    db.delete(share)
    db.commit()


@app.post("/sync/push", response_model=schemas.PushOut)
def sync_push(
    body: schemas.PushIn, user: models.User = Depends(auth.current_user), db: DbSession = Depends(get_db)
) -> schemas.PushOut:
    return sync.push(db, user, body.records)


@app.get("/sync/pull", response_model=schemas.PullOut)
def sync_pull(
    since: int = Query(0, ge=0), user: models.User = Depends(auth.current_user), db: DbSession = Depends(get_db)
) -> schemas.PullOut:
    return sync.pull(db, user, since)
