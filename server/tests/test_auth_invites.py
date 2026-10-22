from conftest import login


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
