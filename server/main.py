from contextlib import asynccontextmanager
import json
import os
import secrets

import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Security, status
from fastapi.security import APIKeyHeader, HTTPAuthorizationCredentials, HTTPBearer

load_dotenv()

GOLEMIO_BASE = "https://api.golemio.cz"
API_KEY = os.environ["GOLEMIO_API_KEY"]
API_TOKEN = os.getenv("API_TOKEN")
STOPS_FILE = "stops.json"
DEPARTURES_LIMIT = 2

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)
http_bearer = HTTPBearer(auto_error=False)


def verify_token(
    header_token: str | None = Security(api_key_header),
    bearer_token: HTTPAuthorizationCredentials | None = Security(http_bearer),
):
    if not API_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="API_TOKEN is not configured on the server",
        )
    token = (bearer_token.credentials if bearer_token else None) or header_token
    if not token or not secrets.compare_digest(token, API_TOKEN):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )


def load_stops() -> list[dict]:
    with open(STOPS_FILE) as f:
        return json.load(f)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http = httpx.AsyncClient(
        base_url=GOLEMIO_BASE,
        headers={"X-Access-Token": API_KEY},
        timeout=10.0,
    )
    yield
    await app.state.http.aclose()


app = FastAPI(lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/departures", dependencies=[Depends(verify_token)])
async def get_departures():
    stops = load_stops()
    results = []

    for stop in stops:
        stop_id = stop["stop_id"]
        tram_lines = set(stop["tram_lines"])

        resp = await app.state.http.get(
            "/v2/pid/departureboards",
            params={
                "ids[]": stop_id,
                "limit": 40,
                "minutesBefore": 0,
                "minutesAfter": 120,
                "mode": "departures",
            },
        )

        if resp.status_code != 200:
            raise HTTPException(
                status_code=resp.status_code,
                detail=f"Golemio error for stop {stop_id}: {resp.text}",
            )

        departures_raw = resp.json().get("departures", [])

        by_line: dict[str, list] = {}
        for dep in departures_raw:
            line = dep.get("route", {}).get("short_name")
            if line not in tram_lines:
                continue
            if line not in by_line:
                by_line[line] = []
            if len(by_line[line]) < DEPARTURES_LIMIT:
                ts = dep.get("departure_timestamp", {})
                by_line[line].append({
                    "scheduled": ts.get("scheduled"),
                    "predicted": ts.get("predicted"),
                    "minutes": ts.get("minutes"),
                    "headsign": dep.get("trip", {}).get("headsign"),
                })

        results.append({
            "stop_id": stop_id,
            "stop_name": stop.get("stop_name"),
            "departures": by_line,
        })

    return results
