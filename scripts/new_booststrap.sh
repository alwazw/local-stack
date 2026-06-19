#!/usr/bin/env bash
# ==============================================================================
# SMART BOOTSTRAP STRATEGY
# Provisions secrets, scaffolds state directories, applies Terraform, and launches.
# ==============================================================================
set -e # Exit on any error
set -u # Exit on undefined variables

# --- Configuration ---
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SECRETS_SHARE_PATH="/mnt/vault/local-stack-secrets" # Change to your actual mount path

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Starting Smart Bootstrap for local-stack...${NC}"

# ==========================================
# PHASE 1: Validate Environment
# ==========================================
echo -e "\n${YELLOW}[1/5] Validating Environment...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Error: docker is required.${NC}"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo -e "${RED}Error: terraform is required.${NC}"; exit 1; }

if [ ! -d "$SECRETS_SHARE_PATH" ]; then
    echo -e "${RED}Error: Secrets share not found at $SECRETS_SHARE_PATH.${NC}"
    echo "Please mount the network share before running bootstrap."
    exit 1
fi

# ==========================================
# PHASE 2: Secret Hydration
# ==========================================
echo -e "\n${YELLOW}[2/5] Hydrating Secrets from Network Share...${NC}"
cp -a "$SECRETS_SHARE_PATH/.env" "$PROJECT_ROOT/.env"
cp -a "$SECRETS_SHARE_PATH/secrets/." "$PROJECT_ROOT/secrets/"

# Secure the secrets (prevents Docker/SSH key permission denied errors)
chmod 600 "$PROJECT_ROOT/.env"
find "$PROJECT_ROOT/secrets" -type f -exec chmod 600 {} \;
echo "Secrets synced and secured."

# ==========================================
# PHASE 3: State Directory Scaffolding
# ==========================================
echo -e "\n${YELLOW}[3/5] Scaffolding Ignored State Directories...${NC}"
# These are the paths from your .gitignore that need to exist before Docker starts
DIRECTORIES=(
    "data"
    "compose/ai/ollama/models"
    "compose/ai/agent-zero/data"
    "compose/ai/agent-zero/work_dir"
    "compose/ai/openwebui/data"
    "compose/security/vaultwarden/data"
    "compose/network/traefik/data"
)

for dir in "${DIRECTORIES[@]}"; do
    TARGET_DIR="$PROJECT_ROOT/$dir"
    if [ ! -d "$TARGET_DIR" ]; then
        mkdir -p "$TARGET_DIR"
        echo "Created: $dir"
    fi
done
# Ensure current user owns these directories so containers don't fail as root
chown -R $(id -u):$(id -g) "$PROJECT_ROOT/compose"

# ==========================================
# PHASE 4: Terraform Base Infrastructure
# ==========================================
echo -e "\n${YELLOW}[4/5] Applying Terraform Infrastructure...${NC}"
cd "$PROJECT_ROOT/terraform"

terraform init -upgrade
terraform validate

# Plan and apply automatically
terraform plan -out=bootstrap.tfplan
terraform apply -auto-approve bootstrap.tfplan
cd "$PROJECT_ROOT"

# ==========================================
# PHASE 5: Docker Stack Deployment
# ==========================================
echo -e "\n${YELLOW}[5/5] Launching Docker Orchestration...${NC}"
docker compose up -d --remove-orphans

echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN}Bootstrap Complete! Stack is initializing.${NC}"
echo -e "${GREEN}=============================================${NC}"