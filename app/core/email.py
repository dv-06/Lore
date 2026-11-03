import re
import unicodedata

MAX_EMAIL_LENGTH = 254
MAX_LOCAL_LENGTH = 64
MAX_DOMAIN_LENGTH = 253

# Conservative ASCII subset of RFC 5321/5322 local parts. Quoted local parts
# and internationalized domains are deliberately rejected so one canonical
# form is stored for every address.
_LOCAL_RE = re.compile(r"^[a-z0-9!#$%&'*+/=?^_`{|}~.-]+$")
_DOMAIN_LABEL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


class InvalidEmailError(ValueError):
    """Raised when an address cannot be normalized to a usable identity."""


def normalize_email(raw: str) -> str:
    """Return the canonical form used as the login identity.

    NFKC normalization, trimming, and lowercasing make addresses compare
    consistently. Plus tags and dots are preserved because the local part is
    opaque and provider-specific.
    """
    if not isinstance(raw, str):
        raise InvalidEmailError("A valid email address is required.")
    value = unicodedata.normalize("NFKC", raw).strip().lower()
    if not value or len(value) > MAX_EMAIL_LENGTH:
        raise InvalidEmailError("A valid email address is required.")
    if not value.isascii():
        raise InvalidEmailError("Email addresses must use ASCII characters.")
    if value.count("@") != 1:
        raise InvalidEmailError("A valid email address is required.")

    local, domain = value.split("@", 1)
    if (
        not local
        or len(local) > MAX_LOCAL_LENGTH
        or not _LOCAL_RE.fullmatch(local)
        or local.startswith(".")
        or local.endswith(".")
        or ".." in local
    ):
        raise InvalidEmailError("A valid email address is required.")

    if (
        not domain
        or len(domain) > MAX_DOMAIN_LENGTH
        or "." not in domain
        or domain.startswith(".")
        or domain.endswith(".")
        or ".." in domain
    ):
        raise InvalidEmailError("A valid email address is required.")

    labels = domain.split(".")
    if any(not _DOMAIN_LABEL_RE.fullmatch(label) for label in labels):
        raise InvalidEmailError("A valid email address is required.")
    if labels[-1].isdigit():
        raise InvalidEmailError("A valid email address is required.")

    return value
