from fastapi import FastAPI
from app.routes import health, check_ins

app = FastAPI(title="Ctrl+Ex+Delete API")
app.include_router(health.router)
app.include_router(check_ins.router)