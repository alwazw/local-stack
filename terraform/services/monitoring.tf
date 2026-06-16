resource "docker_container" "prometheus" {
  name    = "prometheus"
  image   = "prom/prometheus:latest"
  restart = "unless-stopped"

  ports {
    internal = 9090
    external = 9090
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name = docker_network.monitoring.name
  }

  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}

resource "docker_container" "grafana" {
  name    = "grafana"
  image   = "grafana/grafana:latest"
  restart = "unless-stopped"

  ports {
    internal = 3000
    external = 3003
    ip       = "127.0.0.1"
  }

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=admin",
  ]

  networks_advanced {
    name = docker_network.monitoring.name
  }

  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}

resource "docker_container" "uptime_kuma" {
  name    = "uptime-kuma"
  image   = "louislam/uptime-kuma:latest"
  restart = "unless-stopped"

  ports {
    internal = 3001
    external = 3002
    ip       = "127.0.0.1"
  }

  volumes {
    host_path      = docker_volume.uptime_kuma_data.name
    container_path = "/app/data"
  }

  networks_advanced {
    name = docker_network.monitoring.name
  }

  labels = {
    "aef3" = "true"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:3001/api/entry-page"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }
}

resource "docker_container" "loki" {
  name    = "loki"
  image   = "grafana/loki:latest"
  restart = "unless-stopped"
  command = ["-config.file=/etc/loki/config.yaml"]

  ports {
    internal = 3100
    external = 3100
    ip       = "127.0.0.1"
  }

  volumes {
    host_path      = docker_volume.loki_data.name
    container_path = "/loki"
  }

  networks_advanced {
    name = docker_network.monitoring.name
  }

  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "promtail" {
  name    = "promtail"
  image   = "grafana/promtail:latest"
  restart = "unless-stopped"
  command = ["-config.file=/etc/promtail/config.yaml"]

  volumes {
    host_path      = "${path.module}/../compose/monitoring/promtail/config.yaml"
    container_path = "/etc/promtail/config.yaml"
    read_only      = true
  }

  volumes {
    host_path      = "/var/lib/docker/containers"
    container_path = "/var/lib/docker/containers"
    read_only      = true
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.monitoring.name
  }

  depends_on = [docker_container.loki]

  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "cadvisor" {
  name    = "cadvisor"
  image   = "gcr.io/cadvisor/cadvisor:latest"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.monitoring.name
  }

  networks_advanced {
    name = docker_network.proxy.name
  }

  privileged = true

  volumes {
    host_path      = "/"
    container_path = "/rootfs"
    read_only      = true
  }

  volumes {
    host_path      = "/var/run"
    container_path = "/var/run"
    read_only      = true
  }

  volumes {
    host_path      = "/sys"
    container_path = "/sys"
    read_only      = true
  }

  volumes {
    host_path      = "/var/lib/docker/"
    container_path = "/var/lib/docker"
    read_only      = true
  }

  volumes {
    host_path      = "/dev/disk/"
    container_path = "/dev/disk"
    read_only      = true
  }

  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "dozzle" {
  name    = "dozzle"
  image   = "amir20/dozzle:latest"
  restart = "unless-stopped"

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
