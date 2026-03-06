# Engineering Standards

## Scope
Applies to all new code and refactors in this repository.

## General
1. Prefer clear, simple, testable code over clever code.
2. Keep modules cohesive and responsibilities explicit.
3. Refactor for extension points before adding large provider-specific logic.
4. Preserve existing behavior unless fixing a verified bug.

## Dependency and Version Standards
1. Prefer latest stable versions for runtime and tooling.
2. Pin versions for deterministic builds.
3. Document any intentional version holdback and rationale.

## Elixir and Phoenix Standards
1. Keep contexts and boundaries clean.
2. Keep LiveView event handling deterministic.
3. Avoid provider-specific leakage into shared UI components where possible.
4. Remove or avoid logging tokens or sensitive credentials.

## Data and API Standards
1. Validate and normalize external API responses.
2. Handle token expiry and API error paths explicitly.
3. Keep provider field mappings centralized and tested.

## Commit Standards
1. One intent per commit.
2. Use descriptive commit messages.
3. Include doc updates when behavior or setup changes.
