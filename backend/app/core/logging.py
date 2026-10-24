import logging
import sys
from contextvars import ContextVar

request_id_ctx: ContextVar[str | None] = ContextVar("request_id_ctx", default=None)


class RequestIDFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_ctx.get() or "system"
        return True


def setup_logging():
    log_format = "[%(asctime)s] [%(levelname)s] [%(request_id)s] [%(name)s:%(lineno)d] %(message)s"

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter(log_format, datefmt="%Y-%m-%d %H:%M:%S"))
    handler.addFilter(RequestIDFilter())

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)
    root_logger.handlers.clear()
    root_logger.addHandler(handler)

    # Silence verbose 3rd party loggers
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("motor").setLevel(logging.WARNING)


logger = logging.getLogger("aye_kitchen")
