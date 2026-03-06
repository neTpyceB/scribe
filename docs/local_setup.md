# Local Setup

## Prerequisites
1. Docker Desktop (or Docker Engine + Compose plugin).
2. Available local ports:
   - App: `4100`
   - Postgres: `55432`

## First-Time Setup
1. Copy env file:
   ```bash
   cp .env.example .env
   ```
2. Optional: adjust ports in `.env` if already used on your machine (`APP_PORT`, `POSTGRES_PORT`).
3. Start services:
   ```bash
   make up
   ```
4. Open app:
   - `http://localhost:4100`

## Common Commands
1. View logs:
   ```bash
   make logs
   ```
2. Check containers:
   ```bash
   make ps
   ```
3. Run migrations:
   ```bash
   make migrate
   ```
4. Run tests:
   ```bash
   make test
   ```
5. Stop services:
   ```bash
   make down
   ```
6. Stop and remove volumes:
   ```bash
   make clean
   ```

## Notes
1. App runs in Docker and connects to PostgreSQL in a separate container.
2. Host Elixir installation is not required for local runtime.
