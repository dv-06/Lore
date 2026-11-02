from pydantic import BaseModel, ConfigDict, Field


class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=1000)
    max_sources: int = Field(default=5, ge=1, le=10)


class AskDocumentRequest(AskRequest):
    include_related: bool = False


class AskEvidence(BaseModel):
    document_id: str
    filename: str
    title: str | None = None
    location: str | None = None
    snippet: str
    score: float
    reason: str


class AskResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    question: str
    answer: str
    provider: str
    sufficient_evidence: bool
    evidence: list[AskEvidence]
    warnings: list[str] = []


class AskProviderStatus(BaseModel):
    available: bool
    reason: str | None = None


class AskStatusResponse(BaseModel):
    providers: dict[str, AskProviderStatus]
    selected_provider: str
    available: bool
    mode: str = "private"
    local_model_ready: bool = False
    external_provider_configured: bool = False


class AskModeRequest(BaseModel):
    mode: str = Field(default="private")


class AssistPrepareRequest(AskRequest):
    document_id: str | None = None
    include_related: bool = False


class AssistedPrepareResponse(BaseModel):
    request_id: str
    provider: str
    question: str
    proposed_excerpts: list[AskEvidence] = []
    payload_hash: str
    expires_at: str
    status: str = "prepared"


class AssistedConfirmationRequest(BaseModel):
    request_id: str
    approved: bool = False
    question: str | None = None
    excerpts: list[AskEvidence] = []
