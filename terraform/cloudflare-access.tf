# ============================================================
# Cloudflare Access — Zero Trust Authentication for *.wazzan.us
# ============================================================
# Protects ALL subdomains behind the cloudflared tunnel with
# a wildcard Access Application requiring authentication via:
#   1. Email OTP (built-in, no IdP needed)
#   2. GitHub OAuth
#   3. Google OAuth
#
# Prerequisites (manual steps — must exist before terraform apply):
#   - secrets/cf_access_token.txt — API token with Zero Trust + Access permissions
#   - secrets/github_oauth_client_id.txt — GitHub OAuth App client ID
#   - secrets/github_oauth_client_secret.txt — GitHub OAuth App client secret
#   - secrets/google_oauth_client_id.txt — Google OAuth 2.0 client ID
#   - secrets/google_oauth_client_secret.txt — Google OAuth 2.0 client secret
# ============================================================

locals {
  cf_account_id = "65523bc079c3f2d39ca13ea6621cd6ed"
  cf_zone_id    = "c721f2375ff817941db7d022d0cce78f"

  # Allowed email addresses for Email OTP authentication
  allowed_emails = ["wafic@wazzan.us"]

  # Read OAuth secrets from files (created by user manually)
  github_client_id     = trimspace(file("${var.secrets_dir}/github_oauth_client_id.txt"))
  github_client_secret = trimspace(file("${var.secrets_dir}/github_oauth_client_secret.txt"))
  google_client_id     = trimspace(file("${var.secrets_dir}/google_oauth_client_id.txt"))
  google_client_secret = trimspace(file("${var.secrets_dir}/google_oauth_client_secret.txt"))
}

# ── Wildcard Access Application ──────────────────────────────
# Covers all *.wazzan.us subdomains behind the tunnel.
resource "cloudflare_zero_trust_access_application" "wildcard" {
  zone_id            = local.cf_zone_id
  name               = "AEF3 Stack (*.wazzan.us)"
  domain             = "*.wazzan.us"
  type               = "self_hosted"
  session_duration   = "24h"
  app_launcher_visible = false

  # CORS for same-origin API calls
  cors_headers {
    allowed_methods   = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
    allowed_origins   = ["https://*.wazzan.us"]
    allow_credentials = true
    max_age           = 86400
  }
}

# ── GitHub Identity Provider ─────────────────────────────────
resource "cloudflare_zero_trust_access_identity_provider" "github" {
  account_id = local.cf_account_id
  name       = "GitHub"
  type       = "github"

  config {
    client_id     = local.github_client_id
    client_secret = local.github_client_secret
  }
}

# ── Google Identity Provider ─────────────────────────────────
resource "cloudflare_zero_trust_access_identity_provider" "google" {
  account_id = local.cf_account_id
  name       = "Google"
  type       = "google"

  config {
    client_id     = local.google_client_id
    client_secret = local.google_client_secret
  }
}

# ── Access Policy — Allow (Email OTP + GitHub + Google) ─────
# Users can authenticate with any of the three methods.
# Each include block is OR'd — satisfying any one grants access.
resource "cloudflare_zero_trust_access_policy" "allow" {
  application_id = cloudflare_zero_trust_access_application.wildcard.id
  zone_id        = local.cf_zone_id
  name           = "Allow Authenticated Users"
  decision       = "allow"
  precedence     = 1

  # Method 1: Email OTP — sends one-time code to allowed emails
  include {
    email = local.allowed_emails
  }

  # Method 2: GitHub OAuth
  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.github.id]
  }

  # Method 3: Google OAuth
  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.google.id]
  }
}

# ── Outputs ──────────────────────────────────────────────────
output "cloudflare_access" {
  description = "Cloudflare Access configuration details"
  value = {
    application_name = cloudflare_zero_trust_access_application.wildcard.name
    application_domain = cloudflare_zero_trust_access_application.wildcard.domain
    access_url       = "https://${local.cf_account_id}.cloudflareaccess.com"
    session_duration = "24h"
    auth_methods     = ["Email OTP", "GitHub OAuth", "Google OAuth"]
    allowed_emails   = local.allowed_emails
    callback_url     = "https://${local.cf_account_id}.cloudflareaccess.com/cdn-cgi/access/callback"
  }
}
