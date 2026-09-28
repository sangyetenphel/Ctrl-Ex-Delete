from fastapi import FastAPI
from app.routes import health

app = FastAPI(title="Ctrl+Ex+Delete API")
app.include_router(health.router)