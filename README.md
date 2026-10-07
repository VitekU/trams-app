# Trams

A simple departure board for Prague trams — a FastAPI server that aggregates
departure times from the [Golemio API](https://api.golemio.cz/) and a SwiftUI
iOS app that displays them.

## Components

### `server/`

FastAPI backend that fetches upcoming departures for the configured stops and
lines, groups them, and exposes them via a single authenticated endpoint.

- `GET /departures` — departures for all stops (requires `X-API-Key` or Bearer auth)
- `GET /health` — health check

Configuration is read from environment variables (see `Config.example.swift`
in the app for the equivalent pattern):

- `GOLEMIO_API_KEY` — Golemio API key
- `API_TOKEN` — token required by clients for `/departures`

Stops and lines are defined in `server/stops.json`.

Run locally:

```bash
cd server
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
```

Accessible on the LAN at `http://<mac-ip>:8000` when bound to `0.0.0.0`.

### `trams-app/`

SwiftUI iOS app. Each stop is shown as a tile with the line number, and the next
departures with minutes until departure, exact time, and delay indicator
(green = on time, yellow/orange/red = increasingly delayed). Pull-to-refresh
and a toolbar refresh button re-fetch data.

Client configuration lives in `trams-app/trams-app/Config.swift`, which is
gitignored — copy `Config.example.swift` to `Config.swift` and fill in your
server URL and API token.

Open `trams-app/trams-app.xcodeproj` in Xcode and run.

## Deployment

The server is deployed to Render via the included Dockerfile, with
`GOLEMIO_API_KEY` and `API_TOKEN` set as environment variables.

## Attribution

This project has been coded with [opencode](https://opencode.ai) using the
GLM 5.3 model.
