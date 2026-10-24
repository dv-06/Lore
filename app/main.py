import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncIterator

from fastapi import FastAPI

from app.api.middleware import PrivateDocumentResponseMiddleware, RequestBodyLimitMiddleware
from app.api.router import api_router, v1_router
from app.core.config import Settings, settings
from app.core.logging import configure_logging
from app.db.base import Base
from app.db.migrations import initialize_fts5, upgrade_legacy_document_table
from app.db.session import create_database_engine, create_session_factory
from app import models  # noqa: F401 - registers SQLAlchemy models with Base.metadata
from app.services.search import SearchRebuildLimitError, rebuild_search_index
from sqlalchemy import text

logger = logging.getLogger(__name__)


def create_app(app_settings: Settings | None = None) -> FastAPI:
    active_settings = app_settings or settings
    configure_logging(active_settings.log_level)

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        data_dir = Path(active_settings.data_dir).expanduser()
        data_dir.mkdir(parents=True, exist_ok=True)
        (data_dir / "documents").mkdir(parents=True, exist_ok=True)
        _app.state.settings = active_settings
        engine = create_database_engine(active_settings)
        _app.state.engine = engine
        _app.state.session_factory = create_session_factory(engine)
        upgrade_legacy_document_table(engine)
        Base.metadata.create_all(bind=engine)
        _app.state.fts5_available = initialize_fts5(engine)
        if _app.state.fts5_available:
            with create_session_factory(engine)() as db:
                document_count = db.scalar(text("SELECT count(*) FROM documents")) or 0
                index_count = db.scalar(text("SELECT count(*) FROM document_search")) or 0
                if document_count != index_count:
                    try:
                        rebuild_search_index(
                            db,
                            max_documents=active_settings.search_rebuild_max_documents,
                        )
                    except SearchRebuildLimitError:
                        _app.state.fts5_available = False
                        logger.warning(
                            "Search index requires a larger configured rebuild limit"
                        )
        else:
            logger.warning("SQLite FTS5 is unavailable; full-text search is disabled")
        logger.info("LORE backend started")
        try:
            yield
        finally:
            engine.dispose()
            logger.info("LORE backend stopped")

    application = FastAPI(
        title=active_settings.app_name,
        version=active_settings.app_version,
        lifespan=lifespan,
    )
    application.include_router(api_router)
    application.include_router(v1_router, prefix=active_settings.api_v1_prefix)
    application.add_middleware(
        RequestBodyLimitMiddleware,
        upload_path=f"{active_settings.api_v1_prefix.rstrip('/')}/documents",
        max_file_size=active_settings.max_upload_size_bytes,
    )
    application.add_middleware(
        PrivateDocumentResponseMiddleware,
        private_path_prefixes=[
            f"{active_settings.api_v1_prefix.rstrip('/')}/documents",
            f"{active_settings.api_v1_prefix.rstrip('/')}/search",
            f"{active_settings.api_v1_prefix.rstrip('/')}/relationships",
        ],
    )
    return application


app = create_app()
