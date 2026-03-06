# Local Development Target (Docker-First)

## Target State
1. Local development runs via Docker.
2. App and PostgreSQL run in separate containers.
3. App is reachable at `http://localhost:4000`.
4. Setup should not require host-installed Elixir to run the app.

## Expected Components
1. `app` service (Phoenix application).
2. `postgres` service (database).
3. Optional helper services if needed later (mailbox/test tools).

## Operational Requirements
1. One documented startup command for contributors.
2. One documented migration command.
3. One documented test command.
4. Clear `.env`-based configuration.

## Notes
This is a target document. Implementation will follow the execution plan and README updates.
