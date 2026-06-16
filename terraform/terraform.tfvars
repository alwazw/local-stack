domain          = "wazzan.us"
timezone        = "America/Toronto"
secrets_dir     = "../secrets"
postgres_user   = "alwazw"
postgres_db     = "aef3"
ssh_deploy_host = "vm2"
ssh_deploy_user = "alwazw"
ssh_deploy_port = 22

enable_profiles = [
  "ai",
  "security",
  "monitoring",
  "management",
  "ci",
  "productivity",
  "network"
]
