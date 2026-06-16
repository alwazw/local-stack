resource "docker_container" "guacd" {
  name    = "guacd"
  image   = "guacamole/guacd:latest"
  restart = "unless-stopped"

  volumes {
    host_path      = docker_volume.guacd_drive.name
    container_path = "/drive"
  }

  volumes {
    host_path      = docker_volume.guacd_record.name
    container_path = "/record"
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

resource "docker_container" "guacamole" {
  name    = "guacamole"
  image   = "guacamole/guacamole:latest"
  restart = "unless-stopped"

  env = [
    "GUACD_HOSTNAME=guacd",
    "POSTGRESQL_HOSTNAME=postgres",
    "POSTGRESQL_DATABASE=guacamole",
    "POSTGRESQL_USER=${var.postgres_user}",
    "POSTGRESQL_PASSWORD_FILE=/run/secrets/postgres_password",
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

  depends_on = [docker_container.guacd, docker_container.postgres]



  labels = {
    "aef3" = "true"
  }
}
