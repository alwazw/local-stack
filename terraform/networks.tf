# AI Services Network
resource "docker_network" "ai_ml" {
  name   = "ai-ml"
  driver = "bridge"
  labels {
    label = "aef3"
    value = "ai-ml"
  }
  lifecycle {
    ignore_changes = [labels]
  }
}

# Agent Communication Bridge (fixes WSL2 networking issue)
resource "docker_network" "agent_communication" {
  name   = "agent-communication"
  driver = "bridge"
  labels {
    label = "aef3"
    value = "agent-communication"
  }
  lifecycle {
    ignore_changes = [labels]
  }
}

# Proxy Network (Traefik + external services)
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

# Database Network
resource "docker_network" "database" {
  name   = "database"
  driver = "bridge"
  labels {
    label = "aef3"
    value = "database"
  }
  lifecycle {
    ignore_changes = [labels]
  }
}

# Security Network
resource "docker_network" "security" {
  name   = "security"
  driver = "bridge"
  labels {
    label = "aef3"
    value = "security"
  }
  lifecycle {
    ignore_changes = [labels]
  }
}

# Monitoring Network
resource "docker_network" "monitoring" {
  name   = "monitoring"
  driver = "bridge"
  labels {
    label = "aef3"
    value = "monitoring"
  }
  lifecycle {
    ignore_changes = [labels]
  }
}
