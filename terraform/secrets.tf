# Docker secrets require Swarm mode.
# For non-Swarm setups, secrets are bind-mounted as files.
# This file documents the secret-to-file mapping for reference.
#
# Secret files are mounted at /run/secrets/<name> inside containers.
# All files are at ${path.module}/../secrets/ on the host.
#
# cf_api_email      → /run/secrets/cf_api_email
# cf_dns_api_token  → /run/secrets/cf_dns_api_token
# cf_api_key        → /run/secrets/cf_api_key
# cf_tunnel_token   → /run/secrets/cf_tunnel_token
# authentik_secret  → /run/secrets/authentik_secret
# hermes_password   → /run/secrets/hermes_password
# github_token      → /run/secrets/github_token
# agent_zero_key    → /run/secrets/agent_zero_key
# gitea_secret      → /run/secrets/gitea_secret
# guac_admin_pass   → /run/secrets/guac_admin_pass
# litellm_key       → /run/secrets/litellm_key
# n8n_key           → /run/secrets/n8n_key
# webui_secret_key  → /run/secrets/webui_secret_key (file: open_web_ui.txt)
# vw_admin_token    → /run/secrets/vw_admin_token
# postgres_password → /run/secrets/postgres_password
# redis_password    → /run/secrets/redis_password
# ssh_deploy_key    → /run/secrets/ssh_deploy_key

# Local variables for secret file paths (used by services)
locals {
  secrets_dir = "${path.module}/../secrets"
  secret_files = {
    cf_api_email      = "${local.secrets_dir}/cf_api_email.txt"
    cf_dns_api_token  = "${local.secrets_dir}/cf_dns_api_token.txt"
    cf_api_key        = "${local.secrets_dir}/cf_api_key.txt"
    cf_tunnel_token   = "${local.secrets_dir}/cf_tunnel_token.txt"
    cf_access_token   = "${local.secrets_dir}/cf_access_token.txt"
    authentik_secret  = "${local.secrets_dir}/authentik_secret.txt"
    hermes_password   = "${local.secrets_dir}/hermes_password.txt"
    github_token      = "${local.secrets_dir}/github_token.txt"
    agent_zero_key    = "${local.secrets_dir}/agent_zero_key.txt"
    gitea_secret      = "${local.secrets_dir}/gitea_secret.txt"
    guac_admin_pass   = "${local.secrets_dir}/guac_admin_pass.txt"
    litellm_key       = "${local.secrets_dir}/litellm_key.txt"
    n8n_key           = "${local.secrets_dir}/n8n_key.txt"
    webui_secret_key  = "${local.secrets_dir}/open_web_ui.txt"
    vw_admin_token    = "${local.secrets_dir}/vw_admin_token.txt"
    postgres_password = "${local.secrets_dir}/postgres_password.txt"
    redis_password    = "${local.secrets_dir}/redis_password.txt"
    ssh_deploy_key    = "${local.secrets_dir}/ssh_deploy_key"

    # Cloudflare Access OAuth secrets (for Zero Trust identity providers)
    github_oauth_client_id     = "${local.secrets_dir}/github_oauth_client_id.txt"
    github_oauth_client_secret = "${local.secrets_dir}/github_oauth_client_secret.txt"
    google_oauth_client_id     = "${local.secrets_dir}/google_oauth_client_id.txt"
    google_oauth_client_secret = "${local.secrets_dir}/google_oauth_client_secret.txt"
  }
}
