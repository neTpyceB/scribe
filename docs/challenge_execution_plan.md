# Challenge Execution Plan

## Goal
Deliver a complete, production-style submission for the Scribe challenge that is easy to run, easy to review, and clearly demonstrates senior-level engineering quality.

## Progress Tracker

### Completed
1. Added repository AI/contributor operating rules in `AGENTS.md`.
2. Added documentation hub and policy documents in `/docs`.
3. Linked docs hub from `README.md`.
4. Added repository hygiene ignores in `.gitignore` (`.idea`, `.DS_Store`, editor artifacts).
5. Added Docker-first local runtime with separate `app` and `postgres` containers.
6. Added `.env.example` with required environment variables.
7. Added `Makefile` with local operations (`up`, `test`, `migrate`, `logs`, etc.).
8. Added local setup documentation and README quick-start section.
9. Verified app is reachable locally at `http://localhost:4100`.
10. Verified test suite passes in Docker (`12 properties, 226 tests, 0 failures`).
11. Fixed Docker dev image to include `inotify-tools` for clean LiveView dev startup.
12. Normalized markdown links to repo-relative paths for portability across machines.
13. Added GitHub Actions CI workflow with concurrency cancellation and PostgreSQL-backed test run.

### In Progress
1. Salesforce implementation preparation.

### Next Up
1. Add minimal CRM abstraction to preserve HubSpot behavior and enable Salesforce cleanly.
2. Implement Salesforce OAuth connection in settings.
3. Implement Salesforce meeting modal flow (search, suggestions, update).
4. Add Salesforce tests and update docs.

## Phase 1: Environment and Runbook First
1. Add Docker-first local development setup with `docker-compose.yml`.
2. Run app and database in separate containers (`app`, `postgres`).
3. Ensure Phoenix binds to `0.0.0.0` and is reachable at `http://localhost:4000`.
4. Provide one-command startup flow in docs (build, migrate, seed, run).
5. Add `.env.example` with all required environment variables.
6. Verify full local browser flow works from Docker only (no host Elixir dependency).

## Phase 2: External Integrations Setup Guide
1. Document all required service accounts and app setup steps:
   - Google OAuth
   - Recall.ai
   - Gemini
   - HubSpot
   - Salesforce
   - LinkedIn
   - Facebook
2. Document exact OAuth callback URLs for local and deployed environments.
3. Add a “minimum required to pass challenge” path:
   - Google + Recall.ai + Gemini + Salesforce
4. Add troubleshooting for common OAuth failures:
   - Redirect URI mismatch
   - Missing scopes
   - Test user not added
   - Invalid client credentials
5. Add an evaluator checklist for quick setup and validation.

## Phase 3: Baseline Quality Gate (Before New Feature Work)
1. Run current tests as-is.
2. Fix only real bugs and objectively broken tests in the existing codebase.
3. Improve flaky tests where needed (replace sleep-based patterns with deterministic assertions).
4. Add formatting and compile checks to local quality workflow.
5. Create a baseline checkpoint branch/commit before Salesforce feature work.

## Phase 4: CI Workflow
1. Add GitHub Actions workflow to run:
   - `mix format --check-formatted`
   - Compile
   - Test suite
2. Use PostgreSQL service container in CI.
3. Add dependency/build caching to speed up CI.
4. Make CI required for PR readiness.
5. Add CI status badge to README.

## Phase 5: Architecture Prep for Salesforce
1. Introduce a CRM abstraction layer to avoid duplicating HubSpot-specific logic.
2. Keep HubSpot behavior unchanged during refactor.
3. Add/adjust tests to lock existing HubSpot behavior.
4. Remove sensitive token logging and tighten OAuth/API error handling.
5. Preserve current UX where no functional changes are required.

## Phase 6: Implement Salesforce Requirements
1. Add Salesforce OAuth connection in Settings.
2. Design settings integration so future CRMs can be added without major rewrites.
3. Add Salesforce flow on meeting details page:
   - Open modal
   - Search/select Salesforce contact
   - Pull contact record from Salesforce API
4. Generate AI field suggestions from transcript.
5. Show side-by-side existing Salesforce values vs AI suggested updates.
6. Allow field-level selection/edit before submission.
7. Implement `Update Salesforce` sync action to persist selected updates.
8. Keep UX parity/consistency with existing HubSpot flow and challenge expectations.

## Phase 7: Testing for New Functionality
1. Add unit tests for Salesforce API client and field mapping.
2. Add LiveView tests for modal interaction flow:
   - Open modal
   - Search/select contact
   - Render suggestions
   - Submit updates
3. Add error-path tests:
   - Missing/expired token
   - API failures
   - No suggestions detected
4. Ensure all legacy tests and new tests pass together.

## Phase 8: Delivery Packaging and Submission Readiness
1. Rewrite README for evaluator-first onboarding.
2. Add architecture notes explaining key design decisions.
3. Add clear run instructions (Docker + env setup + test + deploy).
4. Add challenge checklist mapping each requirement to implemented feature.
5. Verify deployed app includes working Salesforce flow.
6. Prepare final submission with:
   - Repo link
   - Deployed app link

## Definition of Done
1. `docker compose up` provides a working app at `http://localhost:4000`.
2. Required integrations are documented and configurable.
3. CI is green and validates formatting, compile, and tests.
4. Existing tests pass; Salesforce tests pass.
5. Salesforce feature set satisfies challenge requirements end-to-end.
6. Documentation is clear enough for evaluator setup without manual guidance.
7. Repo and deployed app links are submission-ready.

## Working Rules for This Execution
1. Do not commit planning files until explicitly requested.
2. Keep commits small and traceable once implementation starts.
3. Prioritize reliability and clarity over speed-only shortcuts.
4. Preserve existing behavior unless fixing a verified bug.
5. Continuously verify requirement coverage during implementation.
6. Update this file with explicit progress checkpoints after every relevant implementation step.
7. Execute tasks atomically with strict minimum scope first (e.g., CI test-only before adding extra checks).
