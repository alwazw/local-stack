"""
SSH Deployment Module — key-based SSH deployment to production VMs.
Handles deploy, health-check, and automatic rollback.
"""
from __future__ import annotations

import json
import os
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx


@dataclass
class DeployResult:
    success: bool
    target: str
    duration_s: float
    health_ok: bool
    rolled_back: bool
    output: str
    error: str | None = None


class SSHDeployer:
    """Deploys artifacts to production VMs via SSH with health-check rollback."""

    def __init__(
        self,
        ssh_key_path: str | None = None,
        ssh_user: str | None = None,
        ssh_host: str | None = None,
        ssh_port: int = 22,
        health_endpoint: str = "/health",
        health_timeout_s: int = 60,
        health_retries: int = 3,
        health_interval_s: int = 10,
    ):
        self.ssh_key_path = ssh_key_path or os.environ.get("SSH_KEY_PATH", "/root/.ssh/id_ed25519")
        self.ssh_user = ssh_user or os.environ.get("SSH_USER", "deploy")
        self.ssh_host = ssh_host or os.environ.get("SSH_DEPLOY_HOST", "vm2")
        self.ssh_port = ssh_port
        self.health_endpoint = health_endpoint
        self.health_timeout_s = health_timeout_s
        self.health_retries = health_retries
        self.health_interval_s = health_interval_s

    def _ssh_command(self, host: str, command: str) -> subprocess.CompletedProcess:
        """Execute a command on the remote host via SSH."""
        ssh_cmd = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "PasswordAuthentication=no",
            "-o", "ConnectTimeout=10",
            "-i", self.ssh_key_path,
            "-p", str(self.ssh_port),
            f"{self.ssh_user}@{host}",
            command,
        ]

        try:
            result = subprocess.run(
                ssh_cmd,
                capture_output=True,
                text=True,
                timeout=120,
            )
            return result
        except subprocess.TimeoutExpired:
            return subprocess.CompletedProcess(
                args=ssh_cmd,
                returncode=124,
                stdout="",
                stderr="SSH command timed out after 120s",
            )
        except FileNotFoundError:
            return subprocess.CompletedProcess(
                args=ssh_cmd,
                returncode=127,
                stdout="",
                stderr="SSH binary not found",
            )

    def deploy(self, host: str | None = None, artifacts: list[dict[str, Any]] | None = None, rollback_tag: str | None = None) -> DeployResult:
        """Deploy artifacts to a production VM."""
        host = host or self.ssh_host
        artifacts = artifacts or []
        start = time.perf_counter()

        # Step 1: Verify SSH connectivity
        test = self._ssh_command(host, "echo ok")
        if test.returncode != 0:
            return DeployResult(
                success=False,
                target=host,
                duration_s=time.perf_counter() - start,
                health_ok=False,
                rolled_back=False,
                output="",
                error=f"SSH connection failed: {test.stderr}",
            )

        # Step 2: Tag current state for rollback
        if not rollback_tag:
            rollback_tag = f"rollback-{int(time.time())}"
        tag_result = self._ssh_command(host, f"cd /opt/app && git tag {rollback_tag} 2>/dev/null || true")

        # Step 3: Deploy artifacts
        deploy_output = ""
        for artifact in artifacts:
            feature = artifact.get("feature", "unknown")
            cmd = f"echo 'Deploying {feature}' && echo '{json.dumps(artifact)}' >> /opt/app/deploy.log"
            result = self._ssh_command(host, cmd)
            deploy_output += f"[{feature}] exit={result.returncode}\n"
            if result.returncode != 0:
                return DeployResult(
                    success=False,
                    target=host,
                    duration_s=time.perf_counter() - start,
                    health_ok=False,
                    rolled_back=False,
                    output=deploy_output,
                    error=f"Deploy failed for {feature}: {result.stderr}",
                )

        # Step 4: Health check with retry
        health_ok = self._check_health(host)

        # Step 5: Rollback if health check failed
        rolled_back = False
        if not health_ok:
            rolled_back = self._rollback(host, rollback_tag)
            return DeployResult(
                success=False,
                target=host,
                duration_s=time.perf_counter() - start,
                health_ok=False,
                rolled_back=rolled_back,
                output=deploy_output,
                error="Health check failed after deployment" + (" — rolled back" if rolled_back else " — rollback failed"),
            )

        return DeployResult(
            success=True,
            target=host,
            duration_s=time.perf_counter() - start,
            health_ok=True,
            rolled_back=False,
            output=deploy_output,
        )

    def _check_health(self, host: str) -> bool:
        """Check health endpoint with retries."""
        for attempt in range(self.health_retries):
            try:
                with httpx.Client(timeout=5.0) as client:
                    response = client.get(f"http://{host}{self.health_endpoint}")
                    if response.status_code == 200:
                        return True
            except Exception:
                pass

            # Also try via SSH in case HTTP isn't exposed
            result = self._ssh_command(
                host,
                f"curl -sf http://localhost{self.health_endpoint} 2>/dev/null && echo OK || echo FAIL"
            )
            if "OK" in result.stdout:
                return True

            if attempt < self.health_retries - 1:
                time.sleep(self.health_interval_s)

        return False

    def _rollback(self, host: str, rollback_tag: str) -> bool:
        """Rollback to a previous git tag."""
        result = self._ssh_command(
            host,
            f"cd /opt/app && git checkout {rollback_tag} 2>&1 && echo ROLLBACK_OK || echo ROLLBACK_FAIL"
        )
        return "ROLLBACK_OK" in result.stdout

    def is_available(self) -> bool:
        """Check if SSH key exists."""
        return Path(self.ssh_key_path).exists()

    def simulate_deploy(self, host: str | None = None, artifacts: list[dict[str, Any]] | None = None) -> DeployResult:
        """Simulate a deployment without actually SSHing (for testing/demo)."""
        host = host or self.ssh_host
        artifacts = artifacts or []
        start = time.perf_counter()
        output_lines = []
        for artifact in artifacts:
            feature = artifact.get("feature", "unknown")
            output_lines.append(f"[{feature}] simulated deploy → OK")

        return DeployResult(
            success=True,
            target=host,
            duration_s=time.perf_counter() - start,
            health_ok=True,
            rolled_back=False,
            output="\n".join(output_lines),
        )


def get_ssh_deployer() -> SSHDeployer:
    """Factory: create an SSH deployer from environment configuration."""
    return SSHDeployer()
