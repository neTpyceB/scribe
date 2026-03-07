# Security And Architecture Review

## Date
1. 2026-03-07

## Scope
1. DDoS/bruteforce protections.
2. Auth/session/oauth abuse-path checks.
3. Dependency vulnerability/retirement scan.
4. Architecture failure-mode review for degraded external APIs.

## Findings And Actions
1. Password login bypass vulnerability fixed.
   - Issue: password login accepted any password for an existing email.
   - Action: `UserSessionController` now authenticates with `Accounts.get_user_by_email_and_password/2`.
   - Coverage: controller + accounts tests updated.
2. Password login brute-force protection added.
   - Action: rate-limiter plug added to `POST /users/log_in` (IP-based key).
   - Coverage: controller test validates lockout after repeated attempts.
3. OAuth abuse protections verified.
   - Existing controls confirmed: OAuth request/callback rate limits + state length bound.
4. Session/logout behavior reviewed.
   - Existing controls confirmed: session token invalidation and LiveView disconnect-on-logout flow.
5. TLS enforcement in production hardened.
   - Action: enabled `force_ssl` with `rewrite_on: [:x_forwarded_proto]` and HSTS in `config/prod.exs`.
6. Dependency audit executed.
   - Command: `mix hex.audit`
   - Result: `No retired packages found`.
7. External API degraded-mode architecture reviewed.
   - Existing controls confirmed: centralized timeouts/retries and normalized upstream error mapping.

## Residual Risks
1. `mix hex.audit` covers retired packages but is not a full CVE scanner for all transitive dependencies.
2. Rate limiting is in-memory ETS and not shared across multiple app instances.

## Follow-Up Recommendations
1. Add a secondary dependency CVE scan in CI (for example, an SBOM/CVE workflow).
2. If horizontally scaling app instances, move limiter backend to shared storage (Redis or DB-backed limiter).
