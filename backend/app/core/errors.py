from fastapi import Request
from fastapi.responses import JSONResponse


class AppError(Exception):
    """Error de negocio controlado. Se responde como {"detail": ..., "code": ...} (estándar Aye).

    Los clientes (web e iOS) deciden qué mostrar por `code`, nunca por el texto de `detail`.
    """

    def __init__(self, status_code: int, detail: str, code: str):
        self.status_code = status_code
        self.detail = detail
        self.code = code


async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "code": exc.code},
    )
