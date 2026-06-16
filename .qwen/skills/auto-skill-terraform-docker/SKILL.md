---
name: terraform-docker
description: Terraform infrastructure management for Docker Compose stacks — kreuzwerker/docker provider, non-Swarm secrets, state import, lifecycle rules, and service modules
source: auto-skill
extracted_at: '2026-06-16T15:13:20.271Z'
---

# Terraform Docker Infrastructure

**Core principle:** Use Terraform as the single source of truth for Docker infrastructure (networks, volumes, containers) while keeping Docker Compose for quick testing. Terraform manages 22 resources: 6 networks + 16 volumes + 31 services.

## Directory Structure

```
terraform/
├── providers.tf              # kreuzwerker/docker v3.x
├── variables.tf              # Input variables
├── outputs.tf                # Service URLs, infrastructure summary
├── networks.tf               # 6 Docker networks
├── volumes.tf                # 16 named volumes
├── secrets.tf                # Secret file path mappings (locals)
├── terraform.tfvars          # Environment-specific values
├── modules/
│   └── service/              # Reusable container module
│       ├── main.tf
│       └── outputs.tf
└── services/                 # Service definitions by category
    ├── infrastructure.tf     # traefik, postgres, redis
    ├── ai-core.tf            # 10 AI services
    ├── security.tf           # 3 security services
    ├── monitoring.tf         # 7 monitoring services
    ├── management.tf         # 3 management services
    ├── ci-cd.tf              # 2 CI/CD services
    ├── productivity.tf       # 2 productivity services
    └── network.tf            # 2 network services
```

## Providers Configuration

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}
```

## Critical Gotcha: Docker Secrets Require Swarm Mode

The `kreuzwerker/docker` provider's `docker_secret` resource **requires Docker Swarm mode**. If you're using Docker Compose without Swarm:

```
Error: This node is not a swarm manager.
```

**Solution:** Use bind-mounted volumes instead of `docker_secret` resources:

```hcl
# secrets.tf — maps secret names to file paths (NOT docker_secret resources)
locals {
  secrets_dir = "${path.module}/../secrets"
  secret_files = {
    postgres_password = "${local.secrets_dir}/postgres_password.txt"
    redis_password    = "${local.secrets_dir}/redis_password.txt"
    # ... all 17 secrets
  }
}

# In service definitions — mount secrets as read-only volumes
resource "docker_container" "postgres" {
  # ...
  volumes {
    host_path      = local.secret_files.postgres_password
    container_path = "/run/secrets/postgres_password"
    read_only      = true
  }

  # Or mount entire secrets directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }
}
```

## Importing Existing Resources

When adopting Terraform for an existing Docker Compose stack, **import networks and volumes first** before running `terraform apply`:

```bash
cd terraform/
terraform init

# Import existing networks
terraform import docker_network.ai_ml ai-ml
terraform import docker_network.agent_communication agent-communication
terraform import docker_network.proxy proxy
terraform import docker_network.database database
terraform import docker_network.security security
terraform import docker_network.monitoring monitoring

# Import existing volumes (16 total)
terraform import docker_volume.authentik_media authentik_media
terraform import docker_volume.hermes_home hermes_home
# ... repeat for all volumes
```

**Without importing**, `terraform apply` will try to destroy and recreate existing networks/volumes, which will fail with "network already exists" errors.

## Network Lifecycle Rules

Docker networks imported from existing stacks may have different labels than Terraform defines. Use `lifecycle { ignore_changes }` to prevent recreation:

```hcl
resource "docker_network" "proxy" {
  name   = "proxy"
  driver = "bridge"
  labels {
    label = "aef3"
    value = "proxy"
  }
  lifecycle {
    ignore_changes = [labels]
  }
}
```

## Service Module Pattern

Create a reusable module in `modules/service/main.tf`:

```hcl
variable "name"       { type = string }
variable "image"      { type = string }
variable "command"    { type = list(string), default = [] }
variable "entrypoint" { type = list(string), default = [] }
variable "env"        { type = map(string), default = {} }
variable "ports"      { type = map(string), default = {} }
variable "volumes"    { type = list(string), default = [] }
variable "networks"   { type = list(string), default = [] }
variable "labels"     { type = map(string), default = {} }
variable "restart"    { type = string, default = "unless-stopped" }
variable "healthcheck" {
  type = object({
    test         = list(string)
    interval     = string
    timeout      = string
    retries      = number
    start_period = string
  })
  default = null
}

resource "docker_container" "this" {
  name       = var.name
  image      = var.image
  restart    = var.restart
  command    = length(var.command) > 0 ? var.command : null
  entrypoint = length(var.entrypoint) > 0 ? var.entrypoint : null

  dynamic "env" {
    for_each = var.env
    content {
      name  = env.key
      value = env.value
    }
  }

  dynamic "ports" {
    for_each = var.ports
    content {
      internal = split(":", ports.value)[1]
      external = split(":", ports.value)[0]
      ip       = "127.0.0.1"
    }
  }

  dynamic "volumes" {
    for_each = var.volumes
    content {
      host_path      = split(":", volumes.value)[0]
      container_path = split(":", volumes.value)[1]
      read_only      = length(split(":", volumes.value)) > 2 ? split(":", volumes.value)[2] == "ro" : false
    }
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content { name = networks_advanced.value }
  }

  labels = merge(var.labels, {
    "aef3"         = "true"
    "aef3-service" = var.name
  })

  dynamic "healthcheck" {
    for_each = var.healthcheck != null ? [var.healthcheck] : []
    content {
      test         = healthcheck.value.test
      interval     = healthcheck.value.interval
      timeout      = healthcheck.value.timeout
      retries      = healthcheck.value.retries
      start_period = healthcheck.value.start_period
    }
  }
}

output "container_id"   { value = docker_container.this.id }
output "container_name" { value = docker_container.this.name }
```

**⚠ Terraform variable blocks cannot use single-line syntax with multiple arguments.** Each argument must be on its own line:

```hcl
# WRONG — Terraform will reject this
variable "command" { type = list(string), default = [] }

# CORRECT
variable "command" {
  type    = list(string)
  default = []
}
```

## State Management

```bash
# Never commit state files
echo -e "terraform/.terraform/\nterraform/terraform.tfstate\nterraform/terraform.tfstate.backup\nterraform/*.tfplan" >> .gitignore

# View managed resources
terraform state list

# Check for drift
terraform plan  # No changes = infrastructure matches configuration

# Show resource details
terraform state show docker_network.proxy

# Refresh state from real infrastructure
terraform refresh
```

## Deployment Workflow

```bash
# 1. Initialize (downloads provider)
terraform init

# 2. Validate configuration
terraform validate

# 3. Preview changes
terraform plan

# 4. Deploy
terraform apply -auto-approve

# 5. View outputs
terraform output service_endpoints
terraform output local_endpoints
terraform output -json infrastructure_summary
```

## Adding a New Service via Terraform

1. Add service definition to appropriate file in `terraform/services/`
2. Use `networks_advanced { name = docker_network.<name>.name }` for network assignment
3. Mount secrets as volumes:
   ```hcl
   volumes {
     host_path      = local.secret_files.<name>
     container_path = "/run/secrets/<name>"
     read_only      = true
   }
   ```
4. Or mount entire secrets directory before `networks_advanced`:
   ```hcl
   volumes {
     host_path      = local.secrets_dir
     container_path = "/run/secrets"
     read_only      = true
   }
   ```
5. Run `terraform validate && terraform plan`
6. Run `terraform apply`

## One-Shot Container Pattern

For containers that run once and exit (like cloudflared-installer):

```hcl
resource "docker_container" "cloudflared_installer" {
  name       = "cloudflared-installer"
  image      = "alpine:latest"
  # ...
  lifecycle {
    ignore_changes = [all]  # Prevent recreation after exit
  }
}
```

## Gitignore for Terraform

```gitignore
# Terraform State (Never commit state!)
terraform/.terraform/
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/*.tfplan
```

Only commit `.tf` files, `.tfvars`, and `.terraform.lock.hcl`.

## Verification

```bash
cd terraform/
terraform validate                    # Configuration valid
terraform plan                        # No drift
terraform output                      # Service URLs visible
terraform output -json infrastructure_summary  # Stack summary
```

Expected output:
```json
{
  "services_count": 31,
  "networks_count": 12,
  "secrets_count": 17,
  "profiles": ["ai", "security", "monitoring", "management", "ci", "productivity", "network"]
}
```

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Invalid single-argument block definition` | Variable block on single line | Split into multi-line block |
| `This node is not a swarm manager` | `docker_secret` requires Swarm | Use bind-mounted volumes instead |
| `network with name X already exists` | Network not imported | `terraform import docker_network.X X` |
| `volume with name X already exists` | Volume not imported | `terraform import docker_volume.X X` |
| `no file exists at "../secrets/X"` | Wrong path reference | Use `${path.module}/../secrets/` not `${var.secrets_dir}/` |
