# Local Development Runtime (Docker-First)

## Implemented State
1. Local development runs via Docker.
2. App and PostgreSQL run in separate containers.
3. App is reachable at `http://localhost:4100`.
4. Setup should not require host-installed Elixir to run the app.

## Components
1. `app` service (Phoenix application).
2. `postgres` service (database).

## Default Local Ports
1. App: `4100` (container `4000`)
2. PostgreSQL: `55432` (container `5432`)

## Operational Commands
1. Start: `make up`
2. Test: `make test`
3. Migrate: `make migrate`
4. Logs: `make logs`
5. Stop: `make down`

Detailed guide: [Local Setup](docs/local_setup.md)
