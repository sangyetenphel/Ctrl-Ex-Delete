import logging
import os

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


# Gemini's prebuilt voices (https://ai.google.dev/gemini-api/docs/speech-generation).
# Gemini silently falls back to its own default for an unknown name, so the
# setting is checked here instead.
GEMINI_VOICES = (
    "Zephyr", "Puck", "Charon", "Kore", "Fenrir", "Leda", "Orus", "Aoede", "Callirrhoe", "Autonoe",
    "Enceladus", "Iapetus", "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi",
    "Laomedeia", "Achernar", "Alnilam", "Schedar", "Gacrux", "Pulcherrima", "Achird",
    "Zubenelgenubi", "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafat",
)
DEFAULT_GEMINI_VOICE = "Vindemiatrix"


class Settings(BaseSettings):
    """
    Reads settings from backend/.env (run uvicorn from the backend/ folder), or
    from the file named by CED_ENV_FILE, e.g. CED_ENV_FILE=.env.staging: one
    switch for the server and every script, so a migration and its seeds can
    never end up in different databases.
    """
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
    gemini_voice: str = DEFAULT_GEMINI_VOICE   # "Gentle". Others: Zephyr (Bright), Achernar (Soft), Sulafat (Warm)
    ced_voice_max_minutes: int = 15        # per call
    ced_voice_max_concurrent: int = 3      # calls at once, whole server
    ced_voice_calls_per_hour: int = 30     # calls started, whole server
    # TEMPORARY: privacy-safe call diagnostics (states, counts, sizes; never audio,
    # transcripts or keys). Set CED_VOICE_DIAGNOSTICS=false to silence.
    ced_voice_diagnostics: bool = False

    @field_validator("gemini_voice")
    @classmethod
    def _known_voice(cls, value: str) -> str:
        for name in GEMINI_VOICES:
            if name.lower() == value.strip().lower():
                return name
        logging.getLogger("ced").warning(
            "GEMINI_VOICE=%r isn't a Gemini voice; using %s instead.", value, DEFAULT_GEMINI_VOICE)
        return DEFAULT_GEMINI_VOICE

    # extra="ignore": an unrelated line in .env must never stop the server.
    model_config = SettingsConfigDict(env_file=os.environ.get("CED_ENV_FILE", ".env"), extra="ignore")

    @property
    def s3_configured(self) -> bool:
        return all(
            (self.aws_access_key_id, self.aws_secret_access_key, self.aws_region, self.s3_bucket)
        )


settings = Settings()
