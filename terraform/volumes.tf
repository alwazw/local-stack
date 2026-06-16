resource "docker_volume" "authentik_media" {
  name = "authentik_media"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "hermes_home" {
  name = "hermes_home"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "hermes_agent_src" {
  name = "hermes_agent_src"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "hermes_workspace" {
  name = "hermes_workspace"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "omniroute_data" {
  name = "omniroute_data"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "grafana_data" {
  name = "grafana_data"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "uptime_kuma_data" {
  name = "uptime_kuma_data"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "qdrant_data" {
  name = "qdrant_data"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "guacd_drive" {
  name = "guacd_drive"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "guacd_record" {
  name = "guacd_record"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "gitea_data" {
  name = "gitea_data"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "n8n_data" {
  name = "n8n_data"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "loki_data" {
  name = "loki_data"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "portainer_data" {
  name = "portainer_data"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "dockge_data" {
  name = "dockge_data"
  labels {
    label = "aef3"
    value = "volume"
  }
}

resource "docker_volume" "cloudflared_bin" {
  name = "cloudflared_bin"
  labels {
    label = "aef3"
    value = "volume"
  }
}
