# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the Docker Compose stack.

## Records

| ADR | Title | Date | Status |
|---|---|---|---|
| [ADR-0001](ADR-0001-modular-compose-architecture.md) | Modular Compose Architecture | 2026-06-16 | Accepted |
| [ADR-0002](ADR-0002-docker-swarm-conversion.md) | Docker Swarm Conversion | 2026-06-26 | Accepted |
| [ADR-0003](ADR-0003-secret-lifecycle-management.md) | Secret Lifecycle Management | 2026-06-15 | Accepted |
| [ADR-0004](ADR-0004-cadvisor-global-mode.md) | cAdvisor Global Mode | 2026-06-26 | Accepted |

## Adding a New ADR

1. Copy this directory's `template.md` (if it exists) or use the existing ADRs as a format guide.
2. Name the file `ADR-NNNN-short-title.md` where NNNN is the next sequential number.
3. Fill in all sections: Problem, Decision, Consequences, Alternatives Considered.
4. Add an entry to this index.
5. Commit with message `docs: add ADR-NNNN — short title`.
