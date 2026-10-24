from fastapi import APIRouter, Query

from app.core.deps import CurrentWorkspace
from app.schemas.summary import MonthlySummaryResponse
from app.services.summary_service import get_monthly_summary

router = APIRouter()


@router.get("/monthly", response_model=MonthlySummaryResponse)
async def get_monthly_summary_endpoint(
    workspace: CurrentWorkspace,
    year: int = Query(..., ge=2000, le=2100),
    month: int = Query(..., ge=1, le=12),
):
    return await get_monthly_summary(workspace, year, month)
