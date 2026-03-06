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
14. Implemented Salesforce OAuth connection in Settings (provider config, strategy, callback persistence, UI, tests).
15. Verified full Docker test suite after Salesforce OAuth step (`12 properties, 232 tests, 0 failures`).
16. Verified local Salesforce OAuth redirect wiring with real client credentials (`/auth/salesforce` includes correct client_id and callback).
17. Added PKCE support for Salesforce OAuth authorization code flow (`code_challenge`/`code_verifier`) to match Salesforce requirements.
18. Added dedicated tests for Salesforce auth callback persistence and PKCE request behavior; full suite green (`12 properties, 235 tests, 0 failures`).
19. Implemented Salesforce contacts API layer (`search/get/update/apply_updates`) via behaviour + concrete client.
20. Added Salesforce API unit tests with mocked HTTP responses; full Docker suite green (`12 properties, 239 tests, 0 failures`).
21. Hardened Railway production startup to enforce migration-before-server with retrying release script and Docker `ENTRYPOINT` wiring.
22. Completed Salesforce modal Step 2: meeting details Salesforce CTA + LiveView open/close state/events with tests.
23. Fixed Railway release startup compatibility by making `rel/env.sh.eex` platform-safe (Fly-only node naming; non-Fly defaults to `RELEASE_DISTRIBUTION=none`).
24. Fixed calendar sync meeting-link detection for Zoom/Meet/Teams by extracting URLs from `hangoutLink`, `location`, `description`, and conference entry points.
25. Restored production endpoint binding fix in `config/runtime.exs` to default to IPv4 on Railway (`PHX_IPV6=true` optional override).
26. Fixed calendar sync stability regression by handling oversized Google event fields safely (truncate/hash) and preventing sync task crashes on persistence errors.
27. Added overflow guards for other external ingest paths (`meetings.title`, `meeting_participants.name/recall_participant_id`, `recall_bots` string fields) plus regression tests.
28. Updated pending-bot filtering to treat `fatal` as terminal so poller does not keep retrying unrecoverable bots.
29. Hardened Railway migration startup for constrained DB plans: migrations now run with `MIGRATION_POOL_SIZE` (default `2`) and production DB queue settings are configurable via env.
30. Fixed Recall polling reliability bug for past-meeting sync: `BotStatusPoller` now safely handles empty `status_changes` payloads, falls back to top-level status/current status, and no longer crashes before creating meetings.
31. Added regression test for Recall payloads with empty `status_changes` to guarantee completed bots still create meeting records.

### In Progress
1. Salesforce meeting modal flow implementation.
2. Step 3: Salesforce modal shell with open/close + empty state tests.

### Next Up
1. Step 3: Add modal shell with open/close + empty state tests.
2. Step 4: Add contact search/select in modal wired to Salesforce API.
3. Step 5: Add transcript-to-suggestion service for Salesforce fields.
4. Step 6: Render existing vs suggested values in modal.
5. Step 7: Add "Update Salesforce" action and persistence.
6. Step 8: Add docs polish + requirement checklist + end-to-end QA notes.
7. Step 9 (scheduled hardening): apply security/performance tightening across new code:
   - strict field allowlists for external update payloads
   - request size/input length bounds
   - server-side rate limiting for auth/search/update actions
   - HTTP timeout/retry policy for external API clients
   - security-focused tests (abuse cases, redaction, boundary tests)

## Salesforce Modal Atomic Plan

1. Step 1: Salesforce API layer
   - Add dedicated module for contact search/fetch/update in Salesforce.
   - Keep interface small and mockable.
   - Add unit tests with mocked HTTP responses.
2. Step 2: Meeting page entry point
   - Add button in meeting details to open Salesforce review flow.
   - Add LiveView assigns/events only; no heavy logic.
3. Step 3: Modal scaffold
   - Add modal container with open/close behavior.
   - Add tests for visibility toggling.
4. Step 4: Contact search/select
   - Add search input and result list.
   - Persist selected contact id and load full record.
5. Step 5: AI suggestions service
   - Add service that takes transcript + contact record and returns suggested field updates.
   - Add deterministic tests for parser/mapping behavior.
6. Step 6: Suggestions UI
   - Render table/list: field, current Salesforce value, suggested value.
   - Add per-field selection toggles for update control.
7. Step 7: Update action
   - Submit selected updates to Salesforce API.
   - Show success/error feedback and refresh local modal state.
8. Step 8: Finalize docs and verification
   - Update README + docs with Salesforce setup and usage.
   - Add requirement traceability checklist and smoke-test script.

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
