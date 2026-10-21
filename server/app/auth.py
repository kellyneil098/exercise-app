import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from typing import Annotated

import httpx
import jwt
from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session as DbSession

from . import models
from .config import settings
from .db import get_db

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I


def new_invite_code() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(8))


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def issue_token(db: DbSession, user: models.User, device_name: str) -> str:
    token = secrets.token_urlsafe(32)
    db.add(models.Session(token_hash=hash_token(token), user_id=user.id, device_name=device_name[:120]))
    db.commit()
    return token


def current_user(authorization: Annotated[str | None, Header()] = None, db: DbSession = Depends(get_db)) -> models.User:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "missing bearer token")
    sess = db.get(models.Session, hash_token(authorization[7:].strip()))
    if sess is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid token")
    sess.last_seen_at = datetime.now(UTC)
    db.commit()
    return db.get_one(models.User, sess.user_id)


def consume_invite(db: DbSession, code: str | None, new_user: models.User) -> None:
    """Allowlist gate for first sign-in. Raises 403 if the code is bad; creates the shares it promises."""
    s = settings()
    if code is None:
        if s.bootstrap_email and new_user.email and new_user.email.lower() == s.bootstrap_email.lower():
            if db.scalar(select(models.User.id).where(models.User.id != new_user.id).limit(1)) is None:
                return
        raise HTTPException(status.HTTP_403_FORBIDDEN, "invite required")
    inv = db.get(models.Invite, code.strip().upper())
    expires = inv.expires_at.replace(tzinfo=inv.expires_at.tzinfo or UTC) if inv else None
    if inv is None or inv.used_by is not None or expires < datetime.now(UTC):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "invite invalid or expired")
    inv.used_by = new_user.id
    inv.used_at = datetime.now(UTC)
    if inv.grant_view_to_inviter:
        db.add(models.Share(owner_id=new_user.id, viewer_id=inv.created_by))
    if inv.grant_view_of_inviter:
        db.add(models.Share(owner_id=inv.created_by, viewer_id=new_user.id))


def create_invite(db: DbSession, user: models.User, to_inviter: bool, of_inviter: bool) -> models.Invite:
    inv = models.Invite(
        code=new_invite_code(),
        created_by=user.id,
        expires_at=datetime.now(UTC) + timedelta(hours=settings().invite_ttl_hours),
        grant_view_to_inviter=to_inviter,
        grant_view_of_inviter=of_inviter,
    )
    db.add(inv)
    db.commit()
    return inv


_jwks_client: jwt.PyJWKClient | None = None


def verify_apple_identity_token(identity_token: str) -> dict:
    """Validate a Sign in with Apple identity token. Returns the claims (sub, email?)."""
    global _jwks_client
    s = settings()
    if _jwks_client is None:
        _jwks_client = jwt.PyJWKClient(s.apple_jwks_url, cache_keys=True)
    try:
        key = _jwks_client.get_signing_key_from_jwt(identity_token).key
        return jwt.decode(
            identity_token,
            key,
            algorithms=["RS256"],
            audience=s.apple_bundle_id,
            issuer="https://appleid.apple.com",
        )
    except (jwt.PyJWTError, httpx.HTTPError) as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"apple token rejected: {e.__class__.__name__}") from e
