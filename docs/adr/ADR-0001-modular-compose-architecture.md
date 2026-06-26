# ADR-0001: Modular Compose Architecture

**Status:** Accepted  
**Date:** 2026-06-16  
**Context:** Repository overhaul — monolithic to modular migration

## Problem

The root `docker-compose.yml` contained all 14+ service definitions inline. This created several issues:

- Any change to a single service required editing the root file, creating merge conflicts across parallel work streams.
- No way to selectively start/stop service groups (AI, monitoring, security) without commenting out blocks.
- Debugging a single service meant scrolling through hundreds of unrelated YAML lines.
- New service onboarding required modifying the root file, increasing the blast radius of errors.

## Decision

Adopt a **modular composable architecture** using Docker Compose `include:` directives:

- Root `docker-compose.yml` contains **only** `include:` directives, `secrets:`, and `networks:`. Zero service definitions.
- Each service gets its own `compose/<category>/<service>/docker-compose.yml`.
- Services are grouped into 8 categories: `ai`, `ci`, `data`, `management`, `monitoring`, `network`, `productivity`, `security`.
- Selective startup via compose profiles: `docker compose --profile <name> up -d`.

## Consequences

### Positive
- Independent lifecycle management per service — add/remove without touching root file.
- Parallel development: different agents/engineers can edit different compose files without conflicts.
- Easier debugging: open one file, see one service.
- Profiles enable resource-conscious development (start only what you need).

### Negative
- Slightly more file I/O on `docker compose up` (31 files vs 1).
- New contributors need to learn the directory convention.
- Cross-service changes (e.g., network wiring) may touch multiple files.

### Mitigations
- `docs/03-ADDING-SERVICES.md` documents the onboarding pattern.
- Root file serves as the single source of truth for shared infrastructure (secrets, networks).

## Alternatives Considered

1. **Monolithic single file** — simple but unscalable beyond ~20 services.
2. **Docker Swarm stacks** — more complex orchestration, not needed for single-node deployments.
3. **YAML anchors/extends** — Compose supports this but doesn't solve file-level separation.
