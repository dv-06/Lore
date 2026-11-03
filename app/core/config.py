from pathlib import Path

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="LORE_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "LORE"
    app_version: str = "0.1.0"
    api_v1_prefix: str = "/api/v1"
    data_dir: Path = Path("data")
    database_path: Path = Path("data/lore.db")
    # Set this to a PostgreSQL URL to target the multi-user database. When it is
    # empty the SQLite path above remains the source of truth.
    database_url: str | None = None
    database_pool_size: int = Field(default=5, ge=1, le=50)
    database_max_overflow: int = Field(default=10, ge=0, le=100)
    database_pool_recycle_seconds: int = Field(default=1_800, ge=0)
    database_connect_timeout_seconds: int = Field(default=10, ge=1, le=60)
    log_level: str = "INFO"
    max_upload_size_bytes: int = Field(default=20 * 1024 * 1024, gt=0)
    max_extracted_text_chars: int = Field(default=1_000_000, gt=0)
    enable_ocr: bool = False
    relationship_max_documents: int = Field(default=1_000, ge=1, le=5_000)
    relationship_threshold: float = Field(default=0.68, ge=0.5, le=1.0)
    search_rebuild_max_documents: int = Field(default=10_000, ge=1, le=50_000)
    max_ask_question_length: int = Field(default=1_000, gt=0)
    max_ask_sources: int = Field(default=5, ge=1, le=20)
    ask_passage_length: int = Field(default=400, gt=0)
    ask_context_chars: int = Field(default=12_000, gt=0)
    ask_provider: str = "extractive"
    ai_mode: str = "private"
    local_llm_model_path: str | None = None
    local_llm_model_name: str | None = None
    local_llm_endpoint: str = "http://127.0.0.1:11434"
    local_llm_timeout_seconds: int = Field(default=30, gt=0)
    local_llm_max_output_tokens: int = Field(default=256, gt=0)
    local_llm_max_concurrency: int = Field(default=1, ge=1)
    external_ai_provider: str | None = None
    external_ai_endpoint: str | None = None
    external_ai_api_key: str | None = None
    assisted_confirmation_ttl_seconds: int = Field(default=300, gt=0)
    auth_session_ttl_hours: int = Field(default=720, gt=0)
    auth_pairing_code_ttl_minutes: int = Field(default=30, gt=0)
    auth_pairing_max_failures: int = Field(default=5, ge=1, le=100)
    auth_pairing_lockout_seconds: int = Field(default=300, ge=1, le=3_600)
    auth_pairing_max_lockout_seconds: int = Field(default=900, ge=1, le=86_400)
    auth_password_min_length: int = Field(default=12, ge=12, le=64)
    auth_password_max_length: int = Field(default=128, ge=64, le=1_024)
    # Argon2id parameters. 64 MiB / t=3 / p=4 measured at roughly 60 ms on the
    # development host; benchmark again on the target host before deployment.
    auth_password_memory_kib: int = Field(default=65_536, ge=19_456, le=1_048_576)
    auth_password_time_cost: int = Field(default=3, ge=1, le=10)
    auth_password_parallelism: int = Field(default=4, ge=1, le=16)
    invitation_ttl_days: int = Field(default=7, ge=1, le=30)

    @model_validator(mode="after")
    def validate_password_bounds(self) -> "Settings":
        if self.auth_password_min_length >= self.auth_password_max_length:
            raise ValueError(
                "auth_password_min_length must be smaller than "
                "auth_password_max_length"
            )
        return self


settings = Settings()
