import pytest

from app.config import Settings, check_production_safety

PG = "postgresql://u:p@db.example.com/app"


@pytest.fixture(autouse=True)
def _clear_prod_markers(monkeypatch):
    monkeypatch.delenv("FLY_APP_NAME", raising=False)
    monkeypatch.delenv("ENVIRONMENT", raising=False)


@pytest.mark.parametrize("marker", [("FLY_APP_NAME", "exercise-app-api"), ("ENVIRONMENT", "production")])
def test_production_refuses_dev_login(monkeypatch, marker):
    monkeypatch.setenv(*marker)
    with pytest.raises(RuntimeError, match="DEV_LOGIN_ENABLED"):
        check_production_safety(Settings(database_url=PG, dev_login_enabled=True))


def test_production_refuses_sqlite(monkeypatch):
    monkeypatch.setenv("FLY_APP_NAME", "exercise-app-api")
    with pytest.raises(RuntimeError, match="DATABASE_URL"):
        check_production_safety(Settings(database_url="sqlite://", dev_login_enabled=False))


def test_production_allows_safe_config(monkeypatch):
    monkeypatch.setenv("FLY_APP_NAME", "exercise-app-api")
    check_production_safety(Settings(database_url=PG, dev_login_enabled=False))


def test_dev_login_allowed_outside_production():
    check_production_safety(Settings(database_url="sqlite://", dev_login_enabled=True))
