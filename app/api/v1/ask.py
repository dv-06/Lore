from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.db.session import get_db
from app.schemas.ask import (
    AskEvidence,
    AskModeRequest,
    AskRequest,
    AskResponse,
    AskStatusResponse,
    AssistPrepareRequest,
    AssistedConfirmationRequest,
    AssistedPrepareResponse,
)
from app.services.ask import (
    ExternalAIProvider,
    ExtractiveAnswerProvider,
    LocalLLMProvider,
    ProviderUnavailableError,
    answer_question,
    cancel_assisted_request,
    confirm_assisted_request,
    prepare_assisted_request,
    revoke_assisted_requests,
    select_answer_provider,
    validate_question,
)

router = APIRouter()
DbSession = Annotated[Session, Depends(get_db)]


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


@router.post("/ask", response_model=AskResponse)
def ask_question(
    payload: AskRequest,
    db: DbSession,
    request_settings: Annotated[Settings, Depends(get_settings)],
) -> AskResponse:
    try:
        question = validate_question(payload.question, request_settings.max_ask_question_length)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if payload.max_sources > request_settings.max_ask_sources:
        raise HTTPException(
            status_code=422,
            detail=f"max_sources must be at most {request_settings.max_ask_sources}.",
        )
    try:
        result = answer_question(
            db,
            question=question,
            max_sources=payload.max_sources,
            settings_obj=request_settings,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    evidence = [
        AskEvidence.model_validate(item.__dict__ if hasattr(item, "__dict__") else item)
        for item in result.evidence
    ]
    return AskResponse(
        question=result.question,
        answer=result.answer,
        provider=result.provider,
        sufficient_evidence=result.sufficient_evidence,
        evidence=evidence,
        warnings=result.warnings,
    )


@router.post("/ask/mode")
def set_ai_mode(
    payload: AskModeRequest,
    request: Request,
) -> dict[str, object]:
    settings_obj = request.app.state.settings
    mode = payload.mode.strip().lower()
    if mode not in {"private", "assisted"}:
        raise HTTPException(status_code=422, detail='mode must be "private" or "assisted".')
    if mode == "assisted":
        external_status = ExternalAIProvider(settings_obj).status()
        if not external_status["available"]:
            raise HTTPException(status_code=503, detail=str(external_status["reason"]))
    settings_obj.ai_mode = mode
    selected = select_answer_provider(settings_obj)
    available = True
    if mode == "assisted" or selected == "assisted":
        available = bool(ExternalAIProvider(settings_obj).status()["available"])
    return {
        "mode": mode,
        "selected_provider": selected,
        "available": available,
    }


@router.post("/ask/prepare", response_model=AssistedPrepareResponse)
def prepare_assisted_request_route(
    payload: AssistPrepareRequest,
    db: DbSession,
    request_settings: Annotated[Settings, Depends(get_settings)],
) -> AssistedPrepareResponse:
    if request_settings.ai_mode != "assisted":
        raise HTTPException(status_code=400, detail="Assisted mode is not enabled on this server.")
    provider_status = ExternalAIProvider(request_settings).status()
    if not provider_status["available"]:
        raise HTTPException(status_code=503, detail=str(provider_status["reason"]))
    try:
        question = validate_question(payload.question, request_settings.max_ask_question_length)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    prepared = prepare_assisted_request(
        db,
        question=question,
        max_sources=payload.max_sources,
        settings_obj=request_settings,
        document_id=payload.document_id,
        include_related=payload.include_related,
    )
    return AssistedPrepareResponse(
        request_id=prepared["request_id"],
        provider=prepared["provider"],
        question=prepared["question"],
        proposed_excerpts=[AskEvidence.model_validate(item) for item in prepared["excerpts"]],
        payload_hash=prepared["payload_hash"],
        expires_at=prepared["expires_at"],
    )


@router.post("/ask/confirm")
def confirm_assisted_request_route(
    payload: AssistedConfirmationRequest,
    db: DbSession,
    request_settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, object]:
    if not payload.approved:
        cancel_assisted_request(payload.request_id)
        return {"approved": False, "request_id": payload.request_id, "status": "cancelled"}
    try:
        result = confirm_assisted_request(
            payload.request_id,
            approved=True,
            question=payload.question,
            excerpts=payload.excerpts,
            settings_obj=request_settings,
            db=db,
        )
    except ProviderUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "approved": True,
        "request_id": payload.request_id,
        "provider": result["provider"],
        "answer": result["answer"],
        "status": "confirmed",
    }


@router.post("/ask/cancel")
def cancel_assisted_request_route(
    request: Request,
) -> dict[str, object]:
    request_id = request.query_params.get("request_id")
    if not request_id:
        raise HTTPException(status_code=422, detail="request_id is required.")
    cancelled = cancel_assisted_request(request_id)
    return {"request_id": request_id, "cancelled": cancelled}


@router.post("/ask/revoke-consent")
def revoke_assisted_requests_route(
    request: Request,
) -> dict[str, object]:
    count = revoke_assisted_requests()
    return {"revoked": True, "count": count}


@router.get("/ask/status", response_model=AskStatusResponse)
def ask_status(
    request: Request,
) -> AskStatusResponse:
    settings_obj = request.app.state.settings
    extractive = ExtractiveAnswerProvider(settings_obj).status()
    local_llm = LocalLLMProvider(settings_obj).status()
    external = ExternalAIProvider(settings_obj).status()
    selected_provider = select_answer_provider(settings_obj)
    providers = {
        "extractive": {"available": bool(extractive["available"]), "reason": extractive.get("reason")},
        "local-llm": {"available": bool(local_llm["available"]), "reason": local_llm.get("reason")},
        "external": {"available": bool(external["available"]), "reason": external.get("reason")},
    }
    if settings_obj.ai_mode == "assisted" or selected_provider == "assisted":
        available = bool(external["available"])
    else:
        available = bool(providers[selected_provider]["available"])
    return AskStatusResponse(
        providers=providers,
        selected_provider=selected_provider,
        available=available,
        mode=settings_obj.ai_mode,
        local_model_ready=bool(local_llm["available"]),
        external_provider_configured=bool(external["available"]),
    )
