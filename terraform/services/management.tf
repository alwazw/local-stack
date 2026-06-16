resource "docker_container" "portainer" {
  name    = "portainer"
  image   = "portainer/portainer-ce:latest"
  restart = "unless-stopped"

  ports {
    internal = 9443
    external = 9443
    ip       = "127.0.0.1"
  }

  ports {
    internal = 8000
    external = 8000
    ip       = "0.0.0.0"
  }

  volumes {
    host_path      = docker_volume.portainer_data.name
    container_path = "/data"
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.proxy.name
  }

  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "dockge" {
  name    = "dockge"
  image   = "louislam/dockge:latest"
  restart = "unless-stopped"

  ports {
    internal = 5001
    external = 5001
    ip       = "127.0.0.1"
  }

  env = [
    "DOCKGE_STACKS_DIR=/opt/stacks",
  ]

  volumes {
    host_path      = docker_volume.dockge_data.name
    container_path = "/app/data"
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.proxy.name
  }

  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "homepage" {
  name    = "homepage"
  image   = "ghcr.io/gethomepage/homepage:latest"
  restart = "unless-stopped"

  ports {
    internal = 3000
    external = 3004
    ip       = "127.0.0.1"
  }

  volumes {
    host_path      = "${path.module}/../compose/management/homepage/config"
    container_path = "/app/config"
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.proxy.name
  }

  labels = {
    "aef3" = "true"
  }
}
