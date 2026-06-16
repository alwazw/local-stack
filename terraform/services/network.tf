resource "docker_container" "cloudflared_installer" {
  name       = "cloudflared-installer"
  image      = "alpine:latest"
  restart    = "no"
  entrypoint = ["/bin/sh", "-c"]
  command    = ["apk add --no-cache curl && curl -fSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /data/cloudflared && chmod +x /data/cloudflared"]

  volumes {
    host_path      = docker_volume.cloudflared_bin.name
    container_path = "/data"
  }

  lifecycle {
    ignore_changes = all
  }

  labels = {
    "aef3" = "true"
  }
}

resource "docker_container" "cloudflared" {
  name       = "cloudflared"
  image      = "busybox:1.37"
  restart    = "unless-stopped"
  entrypoint = ["/bin/sh", "-c"]
  command    = ["TOKEN=$$(cat /run/secrets/cf_tunnel_token) && exec /usr/local/bin/cloudflared tunnel --no-autoupdate run --token $$TOKEN"]

  volumes {
    host_path      = docker_volume.cloudflared_bin.name
    container_path = "/usr/local/bin"
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

  depends_on = [docker_container.cloudflared_installer]


  labels = {
    "aef3" = "true"
  }
}
