from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Reads settings from backend/.env (run uvicorn from the backend/ folder)."""
    database_url: str
    aws_access_key_id: str
    aws_secret_access_key: str
    aws_region: str
    s3_bucket: str

    model_config = SettingsConfigDict(env_file=".env")


settings = Settings()