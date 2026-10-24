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


settings = Settings()
