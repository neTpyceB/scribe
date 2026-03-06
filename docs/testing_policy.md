# Testing Policy

## Goals
1. Protect existing behavior.
2. Verify new behavior comprehensively.
3. Avoid flaky and timing-sensitive tests.

## Requirements
1. Every new feature requires tests.
2. Every bug fix requires a regression test.
3. New external integration code must include error-path tests.

## Test Pyramid (Practical)
1. Unit tests for pure logic and mapping.
2. Integration tests for context boundaries.
3. LiveView tests for UI flows and event interactions.

## Anti-Patterns
1. Avoid arbitrary `sleep` unless unavoidable.
2. Avoid tests that only assert the app did not crash.
3. Avoid tests tied to real third-party APIs in CI.

## Definition of Done For a Change
1. Relevant tests added or updated.
2. Full test suite passes.
3. Documentation updated when behavior changes.
