resource "docker_container" "traefik" {
  name       = "traefik"
  image      = "traefik:latest"
  restart    = "unless-stopped"
  entrypoint = ["/entrypoint-wrapper.sh"]
  command = [
    "--api.dashboard=true", "--api.insecure=false",
    "--providers.docker=true", "--providers.docker.exposedbydefault=false", "--providers.docker.network=proxy",
    "--entrypoints.web.address=:80", "--entrypoints.web.http.redirections.entrypoint.to=websecure", "--entrypoints.web.http.redirections.entrypoint.scheme=https",
    "--entrypoints.websecure.address=:443", "--entrypoints.websecure.http.tls=true",
    "--certificatesresolvers.cloudflare.acme.dnschallenge=true", "--certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare",
    "--certificatesresolvers.cloudflare.acme.email=wafic@wazzan.us", "--certificatesresolvers.cloudflare.acme.storage=/data/acme.json",
    "--log.level=INFO", "--accesslog=true"
  ]

  ports {
    internal = 80
    external = 80
    ip       = "0.0.0.0"
  }

  ports {
    internal = 443
    external = 443
    ip       = "0.0.0.0"
  }

  ports {
    internal = 8080
    external = 8080
    ip       = "127.0.0.1"
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  volumes {
    host_path      = "${path.module}/../compose/network/traefik/data"
    container_path = "/data"
  }

  volumes {
    host_path      = "${path.module}/../compose/network/traefik/entrypoint-wrapper.sh"
    container_path = "/entrypoint-wrapper.sh"
    read_only      = true
  }

  # Secret files mounted as volumes (non-Swarm mode)
  volumes {
    host_path      = local.secret_files.cf_api_email
    container_path = "/run/secrets/cf_api_email"
    read_only      = true
  }

  volumes {
    host_path      = local.secret_files.cf_dns_api_token
    container_path = "/run/secrets/cf_dns_api_token"
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

  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD", "wget", "--spider", "-q", "http://localhost:8080/ping"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}

resource "docker_container" "postgres" {
  name    = "postgres"
  image   = "postgres:16-alpine"
  restart = "unless-stopped"

  env = [
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_DB=${var.postgres_db}",
    "POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password",
    "PGDATA=/var/lib/postgresql/data/pgdata",
  ]

  volumes {
    host_path      = "${path.module}/../compose/data/postgres/data"
    container_path = "/var/lib/postgresql/data"
  }

  # Secret file mounted as volume
  volumes {
    host_path      = local.secret_files.postgres_password
    container_path = "/run/secrets/postgres_password"
    read_only      = true
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

  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U ${var.postgres_user} -d ${var.postgres_db} || pg_isready -h localhost -U ${var.postgres_user} -d ${var.postgres_db}"]
    interval     = "15s"
    timeout      = "5s"
    retries      = 5
    start_period = "60s"
  }
}

resource "docker_container" "redis" {
  name    = "redis"
  image   = "redis:7-alpine"
  restart = "unless-stopped"
  command = ["sh", "-c", "redis-server --requirepass \"$$(cat /run/secrets/redis_password)\" --appendonly yes"]

  # Secret file mounted as volume
  volumes {
    host_path      = local.secret_files.redis_password
    container_path = "/run/secrets/redis_password"
    read_only      = true
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

  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD", "sh", "-c", "redis-cli -a $$(cat /run/secrets/redis_password) ping"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "15s"
  }
}
