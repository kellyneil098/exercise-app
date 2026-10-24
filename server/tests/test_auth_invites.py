from datetime import UTC, datetime, timedelta

from conftest import login
from sqlalchemy import select

from app import models


def test_bootstrap_then_invite_only(client):
    neil, _ = login(client, "neil@example.com")
    assert client.get("/me", headers=neil).json()["email"] == "neil@example.com"
    # Second user without invite is rejected.
    r = client.post("/auth/dev", json={"email": "stranger@example.com"})
    assert r.status_code == 403
    inv = client.post("/invites", json={}, headers=neil)
    assert inv.status_code == 201
    code = inv.json()["code"]
    nat, _ = login(client, "natalie@example.com", code)
    # Code is single-use.
    r = client.post("/auth/dev", json={"email": "third@example.com", "invite_code": code})
    assert r.status_code == 403
    shares = client.get("/shares", headers=neil).json()
    assert [u["email"] for u in shares["i_can_view"]] == ["natalie@example.com"]
    assert [u["email"] for u in shares["can_view_me"]] == ["natalie@example.com"]
    nat_shares = client.get("/shares", headers=nat).json()
    assert [u["email"] for u in nat_shares["i_can_view"]] == ["neil@example.com"]


def test_directional_invite_and_revoke(client):
    neil, neil_u = login(client, "neil@example.com")
    code = client.post(
        "/invites", json={"grant_view_to_inviter": True, "grant_view_of_inviter": False}, headers=neil
    ).json()["code"]
    nat, nat_u = login(client, "natalie@example.com", code)
    assert client.get("/shares", headers=nat).json()["i_can_view"] == []
    assert client.get("/shares", headers=neil).json()["i_can_view"][0]["id"] == nat_u["id"]
    assert client.delete(f"/shares/{neil_u['id']}", headers=nat).status_code == 204
    assert client.get("/shares", headers=neil).json()["i_can_view"] == []


def test_bad_token(client):
    assert client.get("/me").status_code == 401
    assert client.get("/me", headers={"Authorization": "Bearer nope"}).status_code == 401


def _session_rows(client):
    from app import db as dbmod

    s = next(client.app.dependency_overrides[dbmod.get_db]())
    return s, s.scalars(select(models.Session)).all()


def test_logout_revokes_only_this_token(client):
    a, _ = login(client, "neil@example.com")
    b, _ = login(client, "neil@example.com")
    assert client.post("/auth/logout", headers=a).status_code == 204
    assert client.get("/me", headers=a).status_code == 401
    assert client.get("/me", headers=b).status_code == 200
    assert client.post("/auth/logout").status_code == 401


def test_logout_all_revokes_every_token(client):
    a, _ = login(client, "neil@example.com")
    b, _ = login(client, "neil@example.com")
    assert client.post("/auth/logout-all", headers=a).status_code == 204
    assert client.get("/me", headers=a).status_code == 401
    assert client.get("/me", headers=b).status_code == 401


def test_token_expires_at_hard_lifetime(client):
    tok, _ = login(client, "neil@example.com")
    s, (row,) = _session_rows(client)
    row.expires_at = datetime.now(UTC) - timedelta(seconds=1)
    s.commit()
    assert client.get("/me", headers=tok).status_code == 401
    assert _session_rows(client)[1] == []


def test_activity_does_not_extend_hard_lifetime(client):
    tok, _ = login(client, "neil@example.com")
    s, (row,) = _session_rows(client)
    expires = row.expires_at
    assert client.get("/me", headers=tok).status_code == 200
    s.refresh(row)
    assert row.expires_at == expires


def test_idle_token_expires(client):
    tok, _ = login(client, "neil@example.com")
    s, (row,) = _session_rows(client)
    row.last_seen_at = datetime.now(UTC) - timedelta(days=31)
    s.commit()
    assert client.get("/me", headers=tok).status_code == 401
