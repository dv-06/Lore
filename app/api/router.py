from fastapi import APIRouter

from app.api.routes import root_router
from app.api.v1.categories import router as categories_router
from app.api.v1.documents import router as documents_router
from app.api.v1.relationships import router as relationships_router
from app.api.v1.search import router as search_router
from app.api.v1.system import router as system_router

api_router = APIRouter()
api_router.include_router(root_router)

v1_router = APIRouter()
v1_router.include_router(categories_router, prefix="/categories", tags=["categories"])
v1_router.include_router(search_router, prefix="/search", tags=["search"])
v1_router.include_router(relationships_router, tags=["relationships"])
v1_router.include_router(system_router, prefix="/system", tags=["system"])
v1_router.include_router(documents_router, prefix="/documents", tags=["documents"])
