import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncIterator

from fastapi import FastAPI

from app.api.middleware import PrivateDocumentResponseMiddleware, RequestBodyLimitMiddleware
from app.api.router import api_router, v1_router
from app.core.config import Settings, settings
from app.core.logging import configure_logging
from app.db.schema import verify_database_schema
from app.db.session import create_database_engine, create_session_factory
from app.services.auth import AuthManager
from app.services.search import (
    SearchRebuildLimitError,
    rebuild_search_index,
    search_schema_available,
    search_unavailable_message,
)
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
        try:
            _app.state.session_factory = create_session_factory(engine)
            # Schema changes are explicit operator actions. Refuse to start
            # against an unversioned or outdated database instead of altering
            # it in place.
            verify_database_schema(engine, active_settings)
            _app.state.auth = AuthManager(active_settings)
            with create_session_factory(engine)() as db:
                _app.state.auth.bootstrap(db)
            if _app.state.auth.pairing_code_path.is_file():
                logger.info(
                    "LORE is awaiting device pairing; pairing code stored at %s",
                    _app.state.auth.pairing_code_path,
                )
            _app.state.search_available = search_schema_available(engine)
            if _app.state.search_available:
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
                            _app.state.search_available = False
                            logger.warning(
                                "Search index requires a larger configured rebuild limit"
                            )
            else:
                logger.warning(
                    "%s; full-text search is disabled",
                    search_unavailable_message(engine),
                )
        except BaseException:
            engine.dispose()
            raise
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
            f"{active_settings.api_v1_prefix.rstrip('/')}/ask",
            f"{active_settings.api_v1_prefix.rstrip('/')}/auth",
        ],
    )
    return application


app = create_app()
