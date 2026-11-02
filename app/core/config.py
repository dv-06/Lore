from pathlib import Path

from pydantic import Field
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


settings = Settings()
