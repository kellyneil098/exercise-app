from tests.conftest import login


def rec(id, table="location", payload=None, updated_at="2026-01-01T00:00:00Z", op="upsert"):
    return {"id": id, "table": table, "op": op, "payload": payload or {"n": 1}, "updated_at": updated_at}


def test_seqs_unique_and_counter_survives_ignored_pushes(client):
    neil, neil_user = login(client, "neil@example.com")
    a = client.post("/sync/push", json={"records": [rec("a"), rec("b")]}, headers=neil).json()
    assert a == {"accepted": 2, "ignored": 0, "cursor": 2}
    # Fully ignored push does not consume sequence numbers.
    b = client.post("/sync/push", json={"records": [rec("a")]}, headers=neil).json()
    assert b == {"accepted": 0, "ignored": 1, "cursor": 2}
    c = client.post("/sync/push", json={"records": [rec("c")]}, headers=neil).json()
    assert c["cursor"] == 3
    seqs = [r["seq"] for r in client.get("/sync/pull?since=0", headers=neil).json()["records"]]
    assert seqs == [1, 2, 3]


def test_payload_owner_mismatch_ignored(client):
    neil, neil_user = login(client, "neil@example.com")
    me = neil_user["id"]
    r = client.post(
        "/sync/push",
        json={"records": [rec("x", payload={"userId": "someone-else"}), rec("y", payload={"userId": me})]},
        headers=neil,
    ).json()
    assert (r["accepted"], r["ignored"]) == (1, 1)


def test_new_share_exposes_existing_history(client):
    neil, neil_user = login(client, "neil@example.com")
    client.post("/sync/push", json={"records": [rec("h1"), rec("h2")]}, headers=neil)
    code = client.post("/invites", json={"grant_view_of_inviter": True}, headers=neil).json()["code"]
    nat, nat_user = login(client, "nat@example.com", invite_code=code)
    # Natalie's cursor is already past Neil's original seqs; the share re-sequenced them.
    page = client.get("/sync/pull?since=2", headers=nat).json()
    assert sorted(r["id"] for r in page["records"]) == ["h1", "h2"]
    assert set(page["visible_user_ids"]) == {
        client.get("/me", headers=nat).json()["id"],
        client.get("/me", headers=neil).json()["id"],
    }
