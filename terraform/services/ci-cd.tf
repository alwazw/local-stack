resource "docker_container" "gitea" {
  name    = "gitea"
  image   = "gitea/gitea:latest"
  restart = "unless-stopped"

  ports {
    internal = 3000
    external = 3001
    ip       = "127.0.0.1"
  }

  ports {
    internal = 22
    external = 2222
    ip       = "127.0.0.1"
  }

  env = [
    "GITEA__database__DB_TYPE=postgres",
    "GITEA__database__HOST=postgres:5432",
    "GITEA__database__NAME=gitea",
    "GITEA__database__USER=${var.postgres_user}",
    "GITEA__database__PASSWD_FILE=/run/secrets/postgres_password",
  ]

  volumes {
    host_path      = docker_volume.gitea_data.name
    container_path = "/data"
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

  depends_on = [docker_container.postgres]



  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "n8n" {
  name    = "n8n"
  image   = "docker.n8n.io/n8nio/n8n:latest"
  restart = "unless-stopped"

  ports {
    internal = 5678
    external = 5678
    ip       = "127.0.0.1"
  }

  env = [
    "N8N_ENCRYPTION_KEY_FILE=/run/secrets/n8n_key",
    "DB_TYPE=postgresdb",
    "DB_POSTGRESDB_HOST=postgres",
    "DB_POSTGRESDB_DATABASE=n8n",
    "DB_POSTGRESDB_USER=${var.postgres_user}",
    "DB_POSTGRESDB_PASSWORD_FILE=/run/secrets/postgres_password",
  ]

  volumes {
    host_path      = docker_volume.n8n_data.name
    container_path = "/home/node/.n8n"
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

  depends_on = [docker_container.postgres]



  labels = {
    "aef3" = "true"
  }
}
