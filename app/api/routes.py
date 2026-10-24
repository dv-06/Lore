from fastapi import APIRouter, Request

from app.schemas.system import RootResponse

root_router = APIRouter()


@root_router.get("/", response_model=RootResponse, tags=["system"])
def read_root(request: Request) -> RootResponse:
    return RootResponse(
        name=request.app.title,
        version=request.app.version,
        status="ok",
    )

