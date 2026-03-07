# Submission Readiness

## Purpose
Single source of truth for what is completed and ready to submit for the challenge.

## Related QA Artifact
1. End-to-end runbook and evidence template: `docs/end_to_end_qa_notes.md`
2. Security and failure-mode review notes: `docs/security_architecture_review.md`

## Submission Links
1. Repository: `https://github.com/neTpyceB/scribe`
2. Deployed app: `https://scribe.adlerclub.tech/`

## Hard Requirements (DONE)
1. Google login works: `DONE`
2. Upcoming calendar events visible in app: `DONE`
3. Meeting recording toggle works: `DONE`
4. Recall bot scheduling/join flow works: `DONE`
5. Past meetings list is populated: `DONE`
6. Meeting transcript view works: `DONE`
7. AI follow-up email appears on meeting details: `DONE`
8. HubSpot suggestion flow works (connect + suggest): `DONE`
9. Salesforce OAuth connect in Settings works: `DONE`
10. Salesforce contact search/select from meeting modal works: `DONE`
11. AI-generated Salesforce field suggestions shown with current vs suggested values: `DONE`
12. Salesforce updates can be selected and synced to CRM: `DONE`

## Extra Improvements (Beyond Bare Minimum)
1. Salesforce contact search UX now matches HubSpot-style live typing search with dropdown results.
2. Search safety guardrails are in place: minimum query length, capped visible results, and “narrow your search” messaging.
3. Salesforce suggestions are cached by transcript hash to avoid repeated AI calls on the same transcript.
4. Added persisted per-user Salesforce field mappings (`Update mapping`) so users can remap extracted fields without code changes.
5. Added async loading states for search/select/suggestion/update actions to prevent “frozen UI” feel.
6. Added clearer error messages for common failures (expired Salesforce session, Gemini quota/config issues, network/API failures).
7. Added Salesforce account disconnect/reconnect flow in Settings for credential recovery.
8. Hardened data ingest paths with overflow/edge-case handling in meeting sync and polling flows.
9. Improved Railway startup reliability with migration-before-server release startup flow.
10. Docker-first local development workflow implemented (app and Postgres split, Makefile commands, reproducible local setup).
11. Added CI with automated tests and concurrency cancellation.
12. Added and maintained living project docs in `/docs` (execution plan, integration checklist, submission readiness).
13. LinkedIn OAuth integration configured and verified (local + deployment configuration updated).
14. Settings page now supports one-click disconnect for all connected OAuth providers (Google, HubSpot, Salesforce, Facebook, LinkedIn).
15. Facebook OAuth scope handling is now runtime-configurable (`FACEBOOK_OAUTH_SCOPE`) to support staged Meta permission rollout.
16. Security/performance hardening implemented: centralized runtime limits, server-side rate limiting, strict input bounds, CRM field allowlists, and standardized upstream timeout/unavailable error mapping.
17. External API client resilience improved with shared timeout/retry defaults (Gemini/HubSpot/Salesforce/Recall/Google/Facebook/LinkedIn).
18. Settings now show selected Facebook page identity (name + page ID) for operator clarity.
19. Google disconnect flow is hardened: disconnect safely preserves historical meeting/bot records and logs the user out when the last Google account is disconnected.
20. Auth route compatibility improved: legacy/manual `GET /users/log_in` now redirects to `/` to avoid missing-route failures.
21. Password login flow hardened: strict email+password verification and IP-based login rate limiting added to reduce brute-force abuse.
22. CI now runs `mix hex.audit`, and production enables `force_ssl` + HSTS via proxy-aware config.
23. Added Ops Health page (`/dashboard/health`) to surface runtime DB health, system load signals, provider connection status, Oban job state/failure summaries, and latest meeting processing readiness.
24. Added replay controls on Ops Health page to manually trigger bot polling, queue AI regeneration for the latest meeting, and reset Salesforce suggestion cache for latest transcript.
25. Added Analytics page (`/dashboard/analytics`) with selectable windows (7/30/90 days), daily meeting and automation volumes, platform posting status distribution, and top automation template usage.

## Test Status
1. Full Docker test suite: green (`12 properties, 283 tests, 0 failures`).
2. Salesforce LiveView flow tests: passing.
3. Salesforce suggestions unit tests: passing.
4. Rate limiter and input guard boundary tests: passing.

## Optional / Showcase Integrations
1. LinkedIn OAuth setup and connection flow: `DONE`
2. Facebook OAuth app setup + local page selection flow: `DONE`
3. Facebook production posting scope (`pages_manage_posts`) verification: `PENDING`
