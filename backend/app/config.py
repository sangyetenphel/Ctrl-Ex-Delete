from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Reads settings from backend/.env (run uvicorn from the backend/ folder)."""
    database_url: str

    # AWS S3 for scrapbook photos. Optional: without them the API still runs,
    # and only the scrapbook photo endpoints answer 503.
    aws_access_key_id: str | None = None
    aws_secret_access_key: str | None = None
    aws_region: str | None = None
    s3_bucket: str | None = None

    model_config = SettingsConfigDict(env_file=".env")

    @property
    def s3_configured(self) -> bool:
        return all(
            (self.aws_access_key_id, self.aws_secret_access_key, self.aws_region, self.s3_bucket)
        )


settings = Settings()
