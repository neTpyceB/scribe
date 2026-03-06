# AGENTS.md

## Purpose
This file defines repository-level working rules for AI coding agents and human contributors.

## Core Rules
1. Prefer Docker-first local development.
2. Keep the database in its own container.
3. Keep documentation current whenever behavior, setup, or architecture changes.
4. Keep tests current for all new code and bug fixes.
5. Do not claim a feature is complete until tested locally and documented.
6. Avoid destructive git operations unless explicitly requested.

## Versioning Policy
1. Use current stable versions of tools and dependencies where practical.
2. If a version is intentionally not latest stable, document why in `/docs`.
3. Prefer explicit version pinning for reproducibility.

## Development Workflow
1. Read `README.md` first.
2. Read `/docs/index.md` next.
3. Follow `/docs/challenge_execution_plan.md` for implementation sequence.
4. Keep commits focused and small.
5. Update docs in the same change when relevant.

## Testing Requirements
1. New behavior requires tests.
2. Bug fixes require regression tests.
3. Avoid flaky tests and arbitrary sleeps.
4. Run tests before marking work as done.

## Documentation Requirements
1. `README.md` is the entrypoint and must remain accurate.
2. `/docs` stores detailed behavior, setup, architecture, and operational notes.
3. Any change to setup, integrations, workflows, or architecture must update docs.

## Communication Requirements (For AI Agents)
1. Ask clarifying questions when a missing decision can cause wrong implementation.
2. State assumptions clearly when proceeding without answers.
3. Surface risks early.
4. Keep explanations concise and actionable.
