from fastapi import FastAPI
from app.routes import health, check_ins, recommendations, activities

app = FastAPI(title="Ctrl+Ex+Delete API")
app.include_router(health.router)
app.include_router(check_ins.router)
app.include_router(recommendations.router)
app.include_router(activities.router)