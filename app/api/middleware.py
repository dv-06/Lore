from tempfile import SpooledTemporaryFile

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class RequestBodyLimitMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        *,
        upload_path: str,
        max_file_size: int,
        multipart_overhead: int = 64 * 1024,
    ) -> None:
        self.app = app
        self.upload_path = upload_path
        self.max_request_size = max_file_size + multipart_overhead

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if (
            scope["type"] != "http"
            or scope["method"] != "POST"
            or scope["path"] != self.upload_path
        ):
            await self.app(scope, receive, send)
            return

        content_length = next(
            (
                value
                for key, value in scope.get("headers", [])
                if key.lower() == b"content-length"
            ),
            None,
        )
        if content_length is not None:
            try:
                if int(content_length) > self.max_request_size:
                    await self._too_large(scope, receive, send)
                    return
            except ValueError:
                pass

        with SpooledTemporaryFile(max_size=1024 * 1024, mode="w+b") as buffered_body:
            received_bytes = 0
            while True:
                message = await receive()
                if message["type"] != "http.request":
                    break
                body = message.get("body", b"")
                received_bytes += len(body)
                if received_bytes > self.max_request_size:
                    await self._too_large(scope, receive, send)
                    return
                buffered_body.write(body)
                if not message.get("more_body", False):
                    break

            buffered_body.seek(0)
            remaining_bytes = received_bytes
            sent_empty_body = False

            async def buffered_receive() -> Message:
                nonlocal remaining_bytes, sent_empty_body
                if remaining_bytes:
                    body = buffered_body.read(min(64 * 1024, remaining_bytes))
                    remaining_bytes -= len(body)
                    return {
                        "type": "http.request",
                        "body": body,
                        "more_body": remaining_bytes > 0,
                    }
                if not sent_empty_body:
                    sent_empty_body = True
                    return {"type": "http.request", "body": b"", "more_body": False}
                return {"type": "http.disconnect"}

            await self.app(scope, buffered_receive, send)

    @staticmethod
    async def _too_large(scope: Scope, receive: Receive, send: Send) -> None:
        response = JSONResponse(
            status_code=413,
            content={"detail": "The uploaded request exceeds the configured size limit."},
        )
        await response(scope, receive, send)


class PrivateDocumentResponseMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        *,
        private_path_prefixes: list[str],
    ) -> None:
        self.app = app
        self.private_path_prefixes = tuple(prefix.rstrip("/") for prefix in private_path_prefixes)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if (
            scope["type"] != "http"
            or not any(
                scope["path"] == prefix or scope["path"].startswith(f"{prefix}/")
                for prefix in self.private_path_prefixes
            )
        ):
            await self.app(scope, receive, send)
            return

        async def private_send(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = [
                    (key, value)
                    for key, value in message.get("headers", [])
                    if key.lower() not in {b"cache-control", b"x-content-type-options"}
                ]
                headers.extend(
                    (
                        (b"cache-control", b"no-store"),
                        (b"x-content-type-options", b"nosniff"),
                    )
                )
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, private_send)
