variable "name" {
  type = string
}

variable "image" {
  type = string
}

variable "command" {
  type    = list(string)
  default = []
}

variable "entrypoint" {
  type    = list(string)
  default = []
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "ports" {
  type    = map(string)
  default = {}
}

variable "volumes" {
  type    = list(string)
  default = []
}

variable "networks" {
  type    = list(string)
  default = []
}

variable "secrets" {
  type = list(object({
    secret_id = string
    filename  = string
    mode      = number
  }))
  default = []
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "restart" {
  type    = string
  default = "unless-stopped"
}

variable "depends_on" {
  type    = list(string)
  default = []
}

variable "healthcheck" {
  type = object({
    test         = list(string)
    interval     = string
    timeout      = string
    retries      = number
    start_period = string
  })
  default = null
}

resource "docker_container" "this" {
  name       = var.name
  image      = var.image
  restart    = var.restart
  command    = length(var.command) > 0 ? var.command : null
  entrypoint = length(var.entrypoint) > 0 ? var.entrypoint : null

  dynamic "env" {
    for_each = var.env
    content {
      name  = env.key
      value = env.value
    }
  }

  dynamic "ports" {
    for_each = var.ports
    content {
      internal = split(":", ports.value)[1]
      external = split(":", ports.value)[0]
      ip       = "127.0.0.1"
    }
  }

  dynamic "volumes" {
    for_each = var.volumes
    content {
      host_path      = split(":", volumes.value)[0]
      container_path = split(":", volumes.value)[1]
      read_only      = length(split(":", volumes.value)) > 2 ? split(":", volumes.value)[2] == "ro" : false
    }
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  dynamic "secret" {
    for_each = var.secrets
    content {
      secret_id = secret.value.secret_id
      filename  = secret.value.filename
      mode      = secret.value.mode
    }
  }

  labels = merge(var.labels, {
    "aef3"         = "true"
    "aef3-service" = var.name
  })

  dynamic "healthcheck" {
    for_each = var.healthcheck != null ? [var.healthcheck] : []
    content {
      test         = healthcheck.value.test
      interval     = healthcheck.value.interval
      timeout      = healthcheck.value.timeout
      retries      = healthcheck.value.retries
      start_period = healthcheck.value.start_period
    }
  }
}
