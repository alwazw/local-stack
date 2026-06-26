# ADR-0004: cAdvisor Global Mode

**Status:** Accepted  
**Date:** 2026-06-26  
**Context:** Monitoring stack — per-node container metrics

## Problem

cAdvisor collects container resource usage metrics (CPU, memory, network, filesystem). In a standalone or single-replica deployment, one cAdvisor instance captures metrics for all containers on that host. However, when the stack migrates to Docker Swarm with multiple nodes:

- A single cAdvisor replica only sees containers on its own node.
- Prometheus scrape targets would miss containers running on other nodes.
- Dashboards would show incomplete or misleading data.

## Decision

Deploy cAdvisor with `deploy.mode: global` in Swarm mode:

```yaml
deploy:
  mode: global
  placement:
    constraints:
      - node.role == worker
```

This ensures **one cAdvisor instance per node**, automatically scaling when nodes are added or removed from the Swarm cluster.

### Configuration

- **Network binding**: Host network mode (`network_mode: host`) so cAdvisor can read `/sys`, `/var/run/docker.sock`, and `/proc` from the host.
- **Privileges**: `privileged: true` required for access to cgroup and filesystem statistics.
- **Scrape target**: Prometheus discovers cAdvisor instances via Docker service labels or static config with node hostname interpolation.

## Consequences

### Positive
- Automatic per-node coverage — no manual configuration when adding nodes.
- Complete metrics across the entire cluster.
- Compatible with Grafana's standard cAdvisor dashboards (designed for multi-node).

### Negative
- Host network mode bypasses Docker network isolation (required trade-off).
- Privileged mode increases attack surface (mitigated by cAdvisor's read-only workload).
- Each node runs a separate cAdvisor process — slightly higher total resource usage vs. a single instance.

## Alternatives Considered

1. **Single replica** — insufficient for multi-node clusters; metrics gaps on non-hosting nodes.
2. **DaemonSet equivalent** — Swarm's `mode: global` is the native equivalent; no alternative needed.
3. **node-exporter only** — collects host metrics but not per-container metrics; cAdvisor fills this gap.
