from pydantic import AliasChoices, Field
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
    # Only for local testing against an S3-compatible server (e.g. MinIO).
    s3_endpoint_url: str | None = None

    # Ced (AI chat). Optional: without a key the API still runs, and only
    # POST /ced/messages answers 503. Switch provider/model here, not in the app.
    ai_provider: str = "groq"
    ai_model: str = Field(default="openai/gpt-oss-120b",
                          validation_alias=AliasChoices("AI_MODEL", "GROQ_MODEL"))
    groq_api_key: str | None = None
    ai_timeout_seconds: float = 20
    ai_max_output_tokens: int = 900        # includes the model's hidden reasoning
    ced_daily_message_limit: int = 60      # per installation, per UTC day
    ced_per_minute_limit: int = 8          # per installation
    ced_global_per_minute_limit: int = 25  # whole server; Groq's free tier allows ~30 RPM

    # Ced voice calls (Gemini Live). Optional: without a key the API still
    # runs, and /ced/voice tells the app voice isn't available.
    gemini_api_key: str | None = None
    gemini_live_model: str = "gemini-3.8-live"
    gemini_voice: str = "Vindemiatrix"     # "Gentle". Alternatives: Achernar (Soft), Sulafat (Warm)
    ced_voice_max_minutes: int = 15        # per call
    ced_voice_max_concurrent: int = 3      # calls at once, whole server

    # extra="ignore": an unrelated line in .env must never stop the server.
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def s3_configured(self) -> bool:
        return all(
            (self.aws_access_key_id, self.aws_secret_access_key, self.aws_region, self.s3_bucket)
        )


settings = Settings()
