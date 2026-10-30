from datetime import UTC, datetime, timedelta

from conftest import login

from app import sync


def rec(id, table="session", op="upsert", payload=None, updated_at="2026-01-01T00:00:00Z"):
    return {"id": id, "table": table, "op": op, "payload": payload or {"v": 1}, "updated_at": updated_at}


def test_push_pull_lww_and_scoping(client):
    neil, neil_u = login(client, "neil@example.com")
    code = client.post("/invites", json={"grant_view_of_inviter": False}, headers=neil).json()["code"]
    nat, nat_u = login(client, "natalie@example.com", code)

    r = client.post("/sync/push", json={"records": [rec("a"), rec("b", table="set_log")]}, headers=neil)
    assert r.json() == {"accepted": 2, "ignored": 0, "cursor": 2}

    # Older write loses, newer wins (LWW).
    r = client.post(
        "/sync/push", json={"records": [rec("a", payload={"v": 0}, updated_at="2025-12-31T00:00:00Z")]}, headers=neil
    )
    assert r.json()["ignored"] == 1
    r = client.post(
        "/sync/push", json={"records": [rec("a", payload={"v": 2}, updated_at="2026-01-02T00:00:00Z")]}, headers=neil
    )
    assert r.json()["accepted"] == 1

    # Natalie cannot overwrite Neil's row, and unknown tables are ignored.
    r = client.post(
        "/sync/push",
        json={"records": [rec("a", payload={"evil": 1}, updated_at="2027-01-01T00:00:00Z"), rec("x", table="nope")]},
        headers=nat,
    )
    assert r.json() == {"accepted": 0, "ignored": 2, "cursor": 3}

    # Neil sees his own rows only (Natalie shares nothing with him in this test).
    pull = client.get("/sync/pull?since=0", headers=neil).json()
    assert [r["id"] for r in pull["records"]] == ["b", "a"]
    assert pull["records"][1]["payload"] == {"v": 2}
    assert pull["cursor"] == 3 and pull["has_more"] is False

    # of_inviter=False: Natalie does NOT view Neil, so she sees nothing yet.
    assert client.get("/sync/pull?since=0", headers=nat).json()["records"] == []

    # Natalie pushes; Neil (viewer of Natalie) pulls it, scoped by user_id.
    client.post("/sync/push", json={"records": [rec("n1", payload={"who": "nat"})]}, headers=nat)
    pull = client.get("/sync/pull?since=3", headers=neil).json()
    assert [(r["id"], r["user_id"]) for r in pull["records"]] == [("n1", nat_u["id"])]
    assert pull["cursor"] == 4

    # Delete is a tombstone.
    client.post(
        "/sync/push",
        json={"records": [rec("b", table="set_log", op="delete", updated_at="2026-02-01T00:00:00Z")]},
        headers=neil,
    )
    pull = client.get("/sync/pull?since=4", headers=neil).json()
    assert pull["records"][0]["deleted"] is True and pull["records"][0]["payload"] == {}


def test_pull_pagination(client):
    neil, _ = login(client, "neil@example.com")
    client.post("/sync/push", json={"records": [rec(f"r{i}") for i in range(600)]}, headers=neil)
    p1 = client.get("/sync/pull?since=0", headers=neil).json()
    assert len(p1["records"]) == 500 and p1["has_more"] is True
    p2 = client.get(f"/sync/pull?since={p1['cursor']}", headers=neil).json()
    assert len(p2["records"]) == 100 and p2["has_more"] is False


def iso(dt):
    return dt.isoformat().replace("+00:00", "Z")


def test_far_future_updated_at_is_clamped(client, monkeypatch):
    neil, _ = login(client, "neil@example.com")
    t0 = datetime(2026, 6, 1, tzinfo=UTC)
    monkeypatch.setattr(sync, "utcnow", lambda: t0)
    client.post(
        "/sync/push",
        json={"records": [rec("p", payload={"v": "pinned"}, updated_at="9999-01-01T00:00:00Z")]},
        headers=neil,
    )
    stored = client.get("/sync/pull?since=0", headers=neil).json()["records"][0]
    assert datetime.fromisoformat(stored["updated_at"].replace("Z", "+00:00")) == t0 + sync.MAX_CLOCK_SKEW

    # Inside the skew window the clamped write still wins LWW...
    r = client.post("/sync/push", json={"records": [rec("p", payload={"v": 1}, updated_at=iso(t0))]}, headers=neil)
    assert r.json()["ignored"] == 1

    # ...but once it has passed, honest writes and deletes correct the row.
    t1 = t0 + sync.MAX_CLOCK_SKEW + timedelta(hours=1)
    monkeypatch.setattr(sync, "utcnow", lambda: t1)
    r = client.post(
        "/sync/push", json={"records": [rec("p", payload={"v": "fixed"}, updated_at=iso(t1))]}, headers=neil
    )
    assert r.json()["accepted"] == 1
    r = client.post(
        "/sync/push", json={"records": [rec("p", op="delete", updated_at=iso(t1 + timedelta(seconds=1)))]}, headers=neil
    )
    assert r.json()["accepted"] == 1
    assert client.get("/sync/pull?since=0", headers=neil).json()["records"][-1]["deleted"] is True


def test_row_pinned_before_clamp_is_overwritable(client, monkeypatch):
    neil, _ = login(client, "neil@example.com")
    monkeypatch.setattr(sync, "utcnow", lambda: datetime(9998, 1, 1, tzinfo=UTC))  # simulate a pre-fix stored row
    client.post("/sync/push", json={"records": [rec("old", updated_at="9999-01-01T00:00:00Z")]}, headers=neil)

    monkeypatch.setattr(sync, "utcnow", lambda: datetime(2026, 6, 1, tzinfo=UTC))
    r = client.post(
        "/sync/push", json={"records": [rec("old", op="delete", updated_at="2026-06-01T00:00:00Z")]}, headers=neil
    )
    assert r.json()["accepted"] == 1
    assert client.get("/sync/pull?since=0", headers=neil).json()["records"][-1]["deleted"] is True
