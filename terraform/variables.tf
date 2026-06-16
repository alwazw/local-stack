variable "domain" {
  description = "Primary domain for the stack"
  type        = string
  default     = "wazzan.us"
}

variable "timezone" {
  description = "System timezone"
  type        = string
  default     = "America/Toronto"
}

variable "secrets_dir" {
  description = "Path to secrets directory"
  type        = string
  default     = "../secrets"
}

variable "enable_profiles" {
  description = "List of compose profiles to enable"
  type        = list(string)
  default     = ["ai", "security", "monitoring", "management", "ci", "productivity", "network"]
}

variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "alwazw"
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
  default     = "aef3"
}

variable "ssh_deploy_host" {
  description = "SSH deployment target hostname"
  type        = string
  default     = "vm2"
}

variable "ssh_deploy_user" {
  description = "SSH deployment username"
  type        = string
  default     = "alwazw"
}

variable "ssh_deploy_port" {
  description = "SSH deployment port"
  type        = number
  default     = 22
}
