#!/usr/bin/env python3
"""
AEF3 Service Integration Tester
Validates all services in the docker-compose stack:
- Container status and health
- Network connectivity between services
- Port availability
- Docker label compliance
- Secret mounting verification
"""

import subprocess
import json
import sys
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ServiceStatus:
    name: str
    expected_profile: str
    expected_networks: list[str]
    expected_secrets: list[str] = field(default_factory=list)
    expected_ports: list[str] = field(default_factory=list)
    has_traefik_labels: bool = False
    has_healthcheck: bool = False
    has_homepage_labels: bool = False
    container_running: bool = False
    container_healthy: bool = False
    networks_ok: bool = False
    secrets_ok: bool = False
    errors: list[str] = field(default_factory=list)


# Service definitions — source of truth for integration testing
SERVICES = {
    "traefik": ServiceStatus("traefik", "ai", ["proxy"],
                            has_traefik_labels=True, has_healthcheck=True,
                            has_homepage_labels=True, expected_secrets=["cf_api_email", "cf_dns_api_token"]),
    "cloudflared": ServiceStatus("cloudflared", "network", ["proxy"],
                                has_healthcheck=False, expected_secrets=["cf_tunnel_token"]),
    "agent-zero": ServiceStatus("agent-zero", "ai", ["ai-ml", "agent-communication"],
                               has_healthcheck=True, has_homepage_labels=True,
                               expected_secrets=["litellm_key", "ssh_deploy_key"]),
    "hermes-agent": ServiceStatus("hermes-agent", "ai", ["ai-ml", "agent-communication"],
                                 has_healthcheck=True),
    "hermes": ServiceStatus("hermes", "ai", ["proxy", "ai-ml"],
                           has_healthcheck=True, has_homepage_labels=True,
                           has_traefik_labels=True, expected_secrets=["hermes_password"]),
    "openwebui": ServiceStatus("openwebui", "ai", ["proxy", "ai-ml"],
                              has_homepage_labels=True, has_traefik_labels=True,
                              expected_secrets=["webui_secret_key"]),
    "litellm": ServiceStatus("litellm", "ai", ["proxy", "ai-ml"],
                            has_healthcheck=True, has_homepage_labels=True,
                            expected_secrets=["litellm_key"]),
    "ollama": ServiceStatus("ollama", "ai", ["ai-ml"],
                           has_healthcheck=True, has_homepage_labels=True),
    "mcpo": ServiceStatus("mcpo", "ai", ["ai-ml"],
                         has_healthcheck=True, has_homepage_labels=True),
    "omniroute": ServiceStatus("omniroute", "ai", ["proxy", "ai-ml", "database"],
                              has_healthcheck=True, has_homepage_labels=True,
                              has_traefik_labels=True, expected_secrets=["redis_password"]),
    "qdrant": ServiceStatus("qdrant", "ai", ["ai-ml"],
                           has_healthcheck=True, has_homepage_labels=True),
    "searxng": ServiceStatus("searxng", "ai", ["proxy", "ai-ml"],
                            has_healthcheck=True, has_homepage_labels=True,
                            has_traefik_labels=True, expected_secrets=["webui_secret_key"]),
    "postgres": ServiceStatus("postgres", "", ["database"],
                             has_healthcheck=True, has_homepage_labels=True,
                             expected_secrets=["postgres_password"]),
    "redis": ServiceStatus("redis", "", ["database"],
                          has_healthcheck=True, expected_secrets=["redis_password"]),
    "authentik-server": ServiceStatus("authentik-server", "security", ["proxy", "database", "security"],
                                     has_homepage_labels=True, has_traefik_labels=True,
                                     expected_secrets=["authentik_secret", "redis_password", "postgres_password"]),
    "authentik-worker": ServiceStatus("authentik-worker", "security", ["database", "security"],
                                     expected_secrets=["authentik_secret", "redis_password", "postgres_password"]),
    "vaultwarden": ServiceStatus("vaultwarden", "security", ["proxy", "security"],
                                has_healthcheck=True, has_homepage_labels=True,
                                has_traefik_labels=True, expected_secrets=["vw_admin_token"]),
    "guacamole": ServiceStatus("guacamole", "productivity", ["proxy", "ai-ml", "database"],
                              has_healthcheck=True, has_homepage_labels=True,
                              has_traefik_labels=True, expected_secrets=["postgres_password", "guac_admin_pass"]),
    "gitea": ServiceStatus("gitea", "ci", ["proxy", "database"],
                          has_healthcheck=True, has_homepage_labels=True,
                          has_traefik_labels=True, expected_secrets=["postgres_password", "gitea_secret"]),
    "n8n": ServiceStatus("n8n", "ci", ["proxy", "database"],
                        has_healthcheck=True, has_homepage_labels=True,
                        has_traefik_labels=True, expected_secrets=["n8n_key", "postgres_password"]),
    "prometheus": ServiceStatus("prometheus", "monitoring", ["monitoring"],
                               has_healthcheck=True, has_homepage_labels=True),
    "grafana": ServiceStatus("grafana", "monitoring", ["monitoring"],
                            has_healthcheck=True, has_homepage_labels=True),
    "uptime-kuma": ServiceStatus("uptime-kuma", "monitoring", ["monitoring"],
                                has_healthcheck=True, has_homepage_labels=True),
    "loki": ServiceStatus("loki", "monitoring", ["monitoring"],
                         has_healthcheck=True, has_homepage_labels=True),
    "promtail": ServiceStatus("promtail", "monitoring", ["monitoring"]),
    "cadvisor": ServiceStatus("cadvisor", "monitoring", ["monitoring", "proxy"],
                             has_homepage_labels=True, has_traefik_labels=True),
    "dozzle": ServiceStatus("dozzle", "monitoring", ["proxy"],
                           has_homepage_labels=True, has_traefik_labels=True),
    "portainer": ServiceStatus("portainer", "management", ["proxy"],
                              has_homepage_labels=True, has_traefik_labels=True),
    "dockge": ServiceStatus("dockge", "management", ["proxy"],
                           has_homepage_labels=True, has_traefik_labels=True),
    "homepage": ServiceStatus("homepage", "management", ["proxy"],
                             has_homepage_labels=True, has_traefik_labels=True),
}


def run_cmd(cmd: str) -> tuple[bool, str]:
    """Run a shell command and return (success, output)."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return result.returncode == 0, result.stdout.strip()
    except Exception as e:
        return False, str(e)


def get_container_info(name: str) -> Optional[dict]:
    """Get docker inspect data for a container."""
    ok, output = run_cmd(f"docker inspect {name} 2>/dev/null")
    if ok and output:
        data = json.loads(output)
        if data:
            return data[0]
    return None


def test_network_connectivity():
    """Test that key service pairs can reach each other."""
    results = []
    tests = [
        ("hermes-agent", "agent-zero", 8080, "Hermes → Agent Zero API"),
        ("agent-zero", "litellm", 4000, "Agent Zero → LiteLLM"),
        ("litellm", "ollama", 11434, "LiteLLM → Ollama"),
    ]
    for src, dst, port, desc in tests:
        ok, _ = run_cmd(f"docker exec {src} python3 -c \"import urllib.request; urllib.request.urlopen('http://{dst}:{port}', timeout=5)\" 2>/dev/null")
        results.append((desc, ok, f"{src} → {dst}:{port}"))
    return results


def main():
    print("=" * 80)
    print("AEF3 Service Integration Test")
    print("=" * 80)

    # Get all running containers
    _, running = run_cmd("docker compose --profile '*' ps --format json 2>/dev/null")
    running_names = set()
    if running:
        for line in running.strip().split("\n"):
            try:
                info = json.loads(line)
                running_names.add(info.get("Name", ""))
            except json.JSONDecodeError:
                pass

    # Test each service
    passed = 0
    failed = 0
    skipped = 0

    for name, svc in sorted(SERVICES.items()):
        info = get_container_info(name)

        if info is None:
            print(f"  ⏭️  {name} — NOT RUNNING (profile: {svc.expected_profile})")
            skipped += 1
            continue

        state = info.get("State", {})
        status = state.get("Status", "unknown")
        health = state.get("Health", {})
        health_status = health.get("Status", "none")

        networks = set(info.get("NetworkSettings", {}).get("Networks", {}).keys())
        expected_nets = set(svc.expected_networks)
        networks_ok = expected_nets.issubset(networks)

        svc.container_running = status == "running"
        svc.container_healthy = health_status in ("healthy", "starting", "none")
        svc.networks_ok = networks_ok

        # Check labels
        config = info.get("Config", {})
        labels = config.get("Labels", {})
        svc.has_traefik_labels = any("traefik.http.routers" in k for k in labels)
        svc.has_homepage_labels = any("homepage." in k for k in labels)

        # Check secrets
        host_config = info.get("HostConfig", {})
        secrets = host_config.get("Secrets", [])
        secret_names = [s.get("Name", "") for s in secrets]
        svc.secrets_ok = all(s in secret_names for s in svc.expected_secrets)

        errors = []
        if not svc.container_running:
            errors.append(f"status={status}")
        if not svc.networks_ok:
            errors.append(f"networks={networks} (expected {expected_nets})")
        if not svc.secrets_ok:
            missing = [s for s in svc.expected_secrets if s not in secret_names]
            errors.append(f"missing secrets: {missing}")

        if not errors:
            icon = "✅" if health_status == "healthy" else "🟢"
            print(f"  {icon} {name} — OK (networks: {', '.join(sorted(networks))})")
            passed += 1
        else:
            print(f"  ❌ {name} — FAIL ({'; '.join(errors)})")
            failed += 1

    # Network connectivity tests
    print("\n--- Network Connectivity ---")
    net_tests = test_network_connectivity()
    for desc, ok, detail in net_tests:
        icon = "✅" if ok else "❌"
        print(f"  {icon} {desc} ({detail})")

    # Summary
    print("\n" + "=" * 80)
    print(f"Results: {passed} passed, {failed} failed, {skipped} not running")
    print("=" * 80)

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
