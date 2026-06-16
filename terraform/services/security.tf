resource "docker_container" "authentik_server" {
  name       = "authentik-server"
  image      = "ghcr.io/goauthentik/server:2024.10.1"
  restart    = "unless-stopped"
  entrypoint = ["/entrypoint-wrapper.sh"]
  command    = ["dumb-init", "--", "ak", "server"]

  ports {
    internal = 9000
    external = 9000
    ip       = "127.0.0.1"
  }

  env = [
    "AUTHENTIK_REDIS__HOST=redis",
    "AUTHENTIK_POSTGRESQL__HOST=postgres",
    "AUTHENTIK_POSTGRESQL__USER=${var.postgres_user}",
    "AUTHENTIK_POSTGRESQL__NAME=authentik",
  ]

  volumes {
    host_path      = docker_volume.authentik_media.name
    container_path = "/media"
  }

  volumes {
    host_path      = "${path.module}/../compose/security/authentik/entrypoint-wrapper.sh"
    container_path = "/entrypoint-wrapper.sh"
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
    name = docker_network.database.name
  }

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.security.name
  }




  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "authentik_worker" {
  name    = "authentik-worker"
  image   = "ghcr.io/goauthentik/server:2024.10.1"
  restart = "unless-stopped"
  command = ["dumb-init", "--", "ak", "worker"]

  env = [
    "AUTHENTIK_REDIS__HOST=redis",
    "AUTHENTIK_POSTGRESQL__HOST=postgres",
    "AUTHENTIK_POSTGRESQL__USER=${var.postgres_user}",
    "AUTHENTIK_POSTGRESQL__NAME=authentik",
  ]

  volumes {
    host_path      = docker_volume.authentik_media.name
    container_path = "/media"
  }

  volumes {
    host_path      = "${path.module}/../compose/security/authentik/entrypoint-wrapper.sh"
    container_path = "/entrypoint-wrapper.sh"
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

  # Secret files directory
  volumes {
    host_path      = local.secrets_dir
    container_path = "/run/secrets"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.security.name
  }

  depends_on = [docker_container.postgres, docker_container.redis]




  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "vaultwarden" {
  name    = "vaultwarden"
  image   = "vaultwarden/server:latest"
  restart = "unless-stopped"

  ports {
    internal = 80
    external = 8082
    ip       = "127.0.0.1"
  }

  env = [
    "DOMAIN=https://vault.wazzan.us",
    "ADMIN_TOKEN_FILE=/run/secrets/vw_admin_token",
    "SIGNUPS_ALLOWED=true",
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
    name = docker_network.security.name
  }


  labels = {
    "aef3" = "true"
  }
}
