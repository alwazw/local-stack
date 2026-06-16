resource "docker_container" "agent_zero" {
  name    = "agent-zero"
  image   = "agent-zero-langgraph:latest"
  restart = "unless-stopped"

  ports {
    internal = 80
    external = 8501
    ip       = "127.0.0.1"
  }

  ports {
    internal = 8080
    external = 8081
    ip       = "127.0.0.1"
  }

  env = [
    "LLM_PROVIDER=openai",
    "LLM_BASE_URL=http://litellm:4000",
    "LLM_MODEL=ollama/llama3.1:8b",
    "QDRANT_HOST=qdrant",
    "MCP_BASE_URL=http://mcpo:8000",
    "SSH_KEY_PATH=/run/secrets/ssh_deploy_key",
    "SSH_USER=deploy",
    "LITELLM_MASTER_KEY_FILE=/run/secrets/litellm_key",
  ]

  volumes {
    host_path      = "${path.module}/../compose/data/agent-zero/data"
    container_path = "/data"
  }

  volumes {
    host_path      = "${path.module}/../compose/data/agent-zero/work_dir"
    container_path = "/work_dir"
  }

  volumes {
    host_path      = "${path.module}/../compose/data/agent-zero/projects/audit"
    container_path = "/projects/audit"
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.agent_communication.name
  }



  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "hermes_agent" {
  name    = "hermes-agent"
  image   = "nousresearch/hermes-agent:latest"
  restart = "unless-stopped"
  command = ["gateway", "run"]

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.agent_communication.name
  }

  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8787/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}

resource "docker_container" "hermes" {
  name       = "hermes"
  image      = "ghcr.io/nesquena/hermes-webui:latest"
  restart    = "unless-stopped"
  entrypoint = ["/entrypoint-wrapper.sh"]
  command    = ["/hermeswebui_init.bash"]

  ports {
    internal = 8787
    external = 8787
    ip       = "127.0.0.1"
  }

  env = [
    "HERMES_WEBUI_STATE_DIR=/home/hermeswebui/.hermes/webui",
    "HERMES_AGENT_HOST=hermes-agent",
  ]

  volumes {
    host_path      = "${path.module}/../compose/data/hermes/home"
    container_path = "/home/hermeswebui/.hermes"
  }

  volumes {
    host_path      = "${path.module}/../compose/data/hermes/hermes_agent_src"
    container_path = "/hermes_agent_src"
  }

  volumes {
    host_path      = "${path.module}/../compose/data/hermes/hermes_workspace"
    container_path = "/hermes_workspace"
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.proxy.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.agent_communication.name
  }

  depends_on = [docker_container.hermes_agent]


  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "litellm" {
  name    = "litellm"
  image   = "ghcr.io/berriai/litellm:main-latest"
  restart = "unless-stopped"

  ports {
    internal = 4000
    external = 4000
    ip       = "127.0.0.1"
  }

  env = [
    "LITELLM_MODEL=ollama/llama3.1:8b",
    "OLLAMA_API_BASE=http://ollama:11434",
    "LITELLM_MASTER_KEY_FILE=/run/secrets/litellm_key",
  ]

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.proxy.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }


  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:4000/health')"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}

resource "docker_container" "ollama" {
  name    = "ollama"
  image   = "ollama/ollama:latest"
  restart = "unless-stopped"

  ports {
    internal = 11434
    external = 11434
    ip       = "127.0.0.1"
  }

  volumes {
    host_path      = "${path.module}/../compose/data/ollama/data"
    container_path = "/root/.ollama"
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }

  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD", "wget", "--spider", "-q", "http://localhost:11434"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}

resource "docker_container" "mcpo" {
  name    = "mcpo"
  image   = "ghcr.io/open-webui/mcpo:latest"
  restart = "unless-stopped"
  command = ["--host", "0.0.0.0", "--port", "8000", "--config", "/app/config.json", "--hot-reload"]

  ports {
    internal = 8000
    external = 8000
    ip       = "127.0.0.1"
  }

  volumes {
    host_path      = "${path.module}/../compose/data/mcpo/config.json"
    container_path = "/app/config.json"
    read_only      = true
  }

  volumes {
    host_path      = "${path.module}/../compose/data/mcpo/filesystem_server.py"
    container_path = "/app/filesystem_server.py"
    read_only      = true
  }

  volumes {
    host_path      = "${path.module}/../compose/data/mcpo/git_server.py"
    container_path = "/app/git_server.py"
    read_only      = true
  }

  volumes {
    host_path      = "${path.module}/../compose/data/mcpo/workspace"
    container_path = "/workspace"
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }

  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8000/docs"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}

resource "docker_container" "openwebui" {
  name    = "openwebui"
  image   = "ghcr.io/open-webui/open-webui:main"
  restart = "unless-stopped"

  ports {
    internal = 8080
    external = 3004
    ip       = "127.0.0.1"
  }

  env = [
    "OLLAMA_BASE_URL=http://ollama:11434",
    "WEBUI_SECRET_KEY_FILE=/run/secrets/webui_secret_key",
  ]

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.proxy.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }


  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "omniroute" {
  name       = "omniroute"
  image      = "diegosouzapw/omniroute:latest"
  restart    = "unless-stopped"
  entrypoint = ["/entrypoint-wrapper.sh"]
  command    = ["node", "dev/run-standalone.mjs"]

  ports {
    internal = 20128
    external = 20128
    ip       = "127.0.0.1"
  }

  env = [
    "REDIS_URL=redis://:${file("${var.secrets_dir}/redis_password.txt")}@redis:6379",
  ]

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.proxy.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.database.name
  }

  depends_on = [docker_container.redis]


  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "qdrant" {
  name    = "qdrant"
  image   = "qdrant/qdrant:latest"
  restart = "unless-stopped"

  ports {
    internal = 6333
    external = 6333
    ip       = "127.0.0.1"
  }

  volumes {
    host_path      = "${path.module}/../compose/data/qdrant/data"
    container_path = "/qdrant/storage"
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }

  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "searxng" {
  name    = "searxng"
  image   = "searxng/searxng:latest"
  restart = "unless-stopped"

  env = [
    "SEARXNG_SECRET_KEY_FILE=/run/secrets/webui_secret_key",
  ]

  volumes {
    host_path      = "${path.module}/../compose/data/searxng/settings.yml"
    container_path = "/etc/searxng/settings.yml"
    read_only      = true
  }

  volumes {
    host_path      = "${path.module}/../compose/data/searxng/limiter.toml"
    container_path = "/etc/searxng/limiter.toml"
    read_only      = true
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.proxy.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.ai_ml.name
  }


  labels = {
    "aef3" = "true"
  }
}
