import pytest
from conftest import login

from app import auth


@pytest.fixture
def apple(client, monkeypatch):
    """POST /auth/apple with the given claims in place of a real Apple identity token."""

    def sign_in(sub, email=None, email_verified=None, invite_code=None, expect=200):
        claims = {"sub": sub}
        if email is not None:
            claims["email"] = email
        if email_verified is not None:
            claims["email_verified"] = email_verified
        monkeypatch.setattr(auth, "verify_apple_identity_token", lambda _tok: claims)
        r = client.post("/auth/apple", json={"identity_token": "x", "invite_code": invite_code, "device_name": "t"})
        assert r.status_code == expect, r.text
        if expect != 200:
            return None, None
        return {"Authorization": f"Bearer {r.json()['token']}"}, r.json()["user"]

    return sign_in


def invite(client, headers):
    return client.post("/invites", json={}, headers=headers).json()["code"]


def test_unverified_email_claim_is_not_stored(client, apple):
    neil, _ = login(client, "neil@example.com")
    _, u = apple("attacker-sub", "victim@example.com", "false", invite(client, neil))
    assert u["email"] is None


def test_unverified_claim_cannot_pre_hijack_victim(client, apple):
    neil, _ = login(client, "neil@example.com")
    attacker, attacker_u = apple("attacker-sub", "victim@example.com", False, invite(client, neil))
    victim, victim_u = apple("victim-sub", "victim@example.com", "true", invite(client, neil))
    assert victim_u["id"] != attacker_u["id"]
    assert victim_u["email"] == "victim@example.com"
    assert client.get("/me", headers=attacker).json()["id"] == attacker_u["id"]


def test_unverified_dev_row_is_not_linked_and_loses_email(client, apple):
    neil, _ = login(client, "neil@example.com")
    planted, planted_u = login(client, "victim@example.com", invite(client, neil))
    _, victim_u = apple("victim-sub", "victim@example.com", True, invite(client, neil))
    assert victim_u["id"] != planted_u["id"]
    assert victim_u["email"] == "victim@example.com"
    assert client.get("/me", headers=planted).json()["email"] is None


def test_verified_row_links_new_apple_identity(client, apple):
    neil, _ = login(client, "neil@example.com")
    _, first = apple("sub-1", "nat@example.com", True, invite(client, neil))
    _, again = apple("sub-2", "nat@example.com", "true")
    assert again["id"] == first["id"]


def test_unverified_claim_cannot_use_bootstrap_email(client, apple):
    apple("sniper-sub", "neil@example.com", False, expect=403)
    _, u = apple("neil-sub", "neil@example.com", True)
    assert u["email"] == "neil@example.com"
