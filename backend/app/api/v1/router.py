from fastapi import APIRouter

from app.api.v1.endpoints import (
    expenses,
    ingredients,
    me,
    orders,
    presentations,
    recipes,
    summary,
    suppliers,
    units,
)

api_router = APIRouter()

# Contrato completo de cada router: docs/api-contract.md
api_router.include_router(me.router, prefix="/me", tags=["Me"])
api_router.include_router(units.router, prefix="/units", tags=["Units"])  # Bloque B1
api_router.include_router(ingredients.router, prefix="/ingredients", tags=["Ingredients"])  # B1
api_router.include_router(suppliers.router, prefix="/suppliers", tags=["Suppliers"])  # B1
api_router.include_router(presentations.router, prefix="/presentations", tags=["Presentations"])  # B2
api_router.include_router(recipes.router, prefix="/recipes", tags=["Recipes"])  # B3
api_router.include_router(orders.router, prefix="/orders", tags=["Orders"])  # B4
api_router.include_router(expenses.router, prefix="/expenses", tags=["Expenses"])  # B4
api_router.include_router(summary.router, prefix="/summary", tags=["Summary"])  # B4
