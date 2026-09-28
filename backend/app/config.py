from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Reads settings from backend/.env (run uvicorn from the backend/ folder)."""
    database_url: str

    model_config = SettingsConfigDict(env_file=".env")


settings = Settings()