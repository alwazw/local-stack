output "service_endpoints" {
  description = "Public-facing service URLs"
  value = {
    traefik    = "https://traefik.${var.domain}"
    homepage   = "https://home.${var.domain}"
    chat       = "https://chat.${var.domain}"
    hermes     = "https://hermes.${var.domain}"
    agent_zero = "http://localhost:8501"
    grafana    = "http://localhost:3003"
    prometheus = "http://localhost:9090"
    gitea      = "https://gitea.${var.domain}"
    n8n        = "https://n8n.${var.domain}"
    vault      = "https://vault.${var.domain}"
    portainer  = "https://portainer.${var.domain}"
    dockge     = "https://dockge.${var.domain}"
    guacamole  = "https://rdp.${var.domain}"
    dozzle     = "https://logs.${var.domain}"
    cadvisor   = "https://cadvisor.${var.domain}"
    search     = "https://search.${var.domain}"
    omniroute  = "https://omniroute.${var.domain}"
  }
}

output "local_endpoints" {
  description = "Localhost-only service URLs"
  value = {
    ollama         = "http://localhost:11434"
    litellm        = "http://localhost:4000"
    mcpo           = "http://localhost:8000"
    qdrant         = "http://localhost:6333"
    postgres       = "localhost:5432"
    redis          = "localhost:6379"
    agent_zero_api = "http://localhost:8081"
  }
}

output "infrastructure_summary" {
  description = "Stack summary"
  value = {
    services_count = 31
    networks_count = 12
    secrets_count  = 17
    profiles       = var.enable_profiles
    domain         = var.domain
  }
}
