import os
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./dev.db"
    # Sign in with Apple: the iOS app's bundle identifier is the JWT audience.
    apple_bundle_id: str = "com.kellyneil.workout"
    apple_jwks_url: str = "https://appleid.apple.com/auth/keys"
    # Development-only password-less login; must be off in production.
    dev_login_enabled: bool = False
    # First-user bootstrap: this email may sign in with no invite (once).
    bootstrap_email: str | None = None
    invite_ttl_hours: int = 72


@lru_cache
def settings() -> Settings:
    s = Settings()
    if os.environ.get("FLY_APP_NAME") and s.database_url.startswith("sqlite"):
        raise RuntimeError("DATABASE_URL must point at Postgres in production; refusing to start on ephemeral SQLite")
    return s
