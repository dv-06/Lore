from fastapi import APIRouter, Depends

from app.api.routes import root_router
from app.api.security import require_auth
from app.api.v1.ask import router as ask_router
from app.api.v1.auth import protected_router as auth_protected_router
from app.api.v1.auth import public_router as auth_public_router
from app.api.v1.categories import router as categories_router
from app.api.v1.documents import router as documents_router
from app.api.v1.relationships import router as relationships_router
from app.api.v1.search import router as search_router
from app.api.v1.system import router as system_router

api_router = APIRouter()
api_router.include_router(root_router)

v1_router = APIRouter()
v1_router.include_router(auth_public_router, prefix="/auth", tags=["auth"])
v1_router.include_router(system_router, prefix="/system", tags=["system"])

protected_router = APIRouter(dependencies=[Depends(require_auth)])
protected_router.include_router(auth_protected_router, prefix="/auth", tags=["auth"])
protected_router.include_router(ask_router, tags=["ask"])
protected_router.include_router(categories_router, prefix="/categories", tags=["categories"])
protected_router.include_router(search_router, prefix="/search", tags=["search"])
protected_router.include_router(relationships_router, tags=["relationships"])
protected_router.include_router(documents_router, prefix="/documents", tags=["documents"])
v1_router.include_router(protected_router)
