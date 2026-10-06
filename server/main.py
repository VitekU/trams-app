from contextlib import asynccontextmanager
import json
import os

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException

load_dotenv()

GOLEMIO_BASE = "https://api.golemio.cz"
API_KEY = os.environ["GOLEMIO_API_KEY"]
STOPS_FILE = "stops.json"
DEPARTURES_LIMIT = 2


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


@app.get("/departures")
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
