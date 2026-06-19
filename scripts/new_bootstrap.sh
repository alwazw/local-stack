#!/usr/bin/env bash
# ==============================================================================
# SMART BOOTSTRAP STRATEGY — Customized for local-stack
# Provisions secrets, scaffolds state directories, applies Terraform, and launches.
# ==============================================================================
set -euo pipefail

# --- Configuration ---
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SECRETS_SHARE_PATH="/mnt/vault/local-stack-secrets" # Change to your actual mount path

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}Starting Smart Bootstrap for local-stack...${NC}"
echo -e "${BLUE}Project root: $PROJECT_ROOT${NC}"

# ==========================================
# PHASE 1: Validate Environment
# ==========================================
echo -e "\n${YELLOW}[1/6] Validating Environment...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Error: docker is required.${NC}"; exit 1; }
command -v docker compose >/dev/null 2>&1 || { echo -e "${RED}Error: docker compose plugin is required.${NC}"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo -e "${RED}Error: terraform is required.${NC}"; exit 1; }

if [ ! -d "$SECRETS_SHARE_PATH" ]; then
    echo -e "${RED}Error: Secrets share not found at $SECRETS_SHARE_PATH.${NC}"
    echo "Please mount the network share before running bootstrap."
    exit 1
fi

# ==========================================
# PHASE 2: Secret Hydration
# ==========================================
echo -e "\n${YELLOW}[2/6] Hydrating Secrets from Network Share...${NC}"

# Sync .env file
if [ -f "$SECRETS_SHARE_PATH/.env" ]; then
    cp -a "$SECRETS_SHARE_PATH/.env" "$PROJECT_ROOT/.env"
    chmod 600 "$PROJECT_ROOT/.env"
    echo "  ✓ Synced .env"
else
    echo -e "${YELLOW}  ⚠ Warning: .env not found in share, using existing if present${NC}"
fi

# Sync secrets directory
if [ -d "$SECRETS_SHARE_PATH/secrets" ]; then
    mkdir -p "$PROJECT_ROOT/secrets"
    cp -a "$SECRETS_SHARE_PATH/secrets/." "$PROJECT_ROOT/secrets/"
    echo "  ✓ Synced secrets/"
else
    echo -e "${YELLOW}  ⚠ Warning: secrets/ not found in share, using existing if present${NC}"
fi

# Secure the secrets (prevents Docker/SSH key permission denied errors)
find "$PROJECT_ROOT/secrets" -type f -exec chmod 600 {} \; 2>/dev/null || true
chmod 600 "$PROJECT_ROOT/.env" 2>/dev/null || true
echo "  ✓ Secrets secured with 600 permissions"

# ==========================================
# PHASE 3: State Directory Scaffolding
# ==========================================
echo -e "\n${YELLOW}[3/6] Scaffolding Ignored State Directories...${NC}"

# These are the paths from your .gitignore that need to exist before Docker starts
# Cross-referenced with all docker-compose.yml bind mounts
DIRECTORIES=(
    # Core data directories (from .gitignore: data/ and compose/*/data/)
    "data"                                    # Root data directory
    
    # Traefik (compose/network/traefik/data)
    "compose/network/traefik/data"
    
    # PostgreSQL (compose/data/postgres/data)
    "compose/data/postgres/data"
    "compose/data/postgres/init"              # Init scripts (tracked but ensure exists)
    
    # Ollama models (compose/ai/ollama/models)
    "compose/ai/ollama/models"
    
    # Agent Zero (compose/ai/agent-zero/data and work_dir)
    "compose/ai/agent-zero/data"
    "compose/ai/agent-zero/work_dir"
    
    # OpenWebUI (compose/ai/openwebui/data)
    "compose/ai/openwebui/data"
    
    # Vaultwarden (compose/security/vaultwarden/data)
    "compose/security/vaultwarden/data"
    
    # Agent Zero external mounts (from compose file: ../../../projects and ../../../agents/qwen)
    "projects"
    "agents/qwen"
    
    # Authentik custom templates (from compose file: ./custom-templates)
    "compose/security/authentik/custom-templates"
)

for dir in "${DIRECTORIES[@]}"; do
    TARGET_DIR="$PROJECT_ROOT/$dir"
    if [ ! -d "$TARGET_DIR" ]; then
        mkdir -p "$TARGET_DIR"
        echo "  ✓ Created: $dir"
    else
        echo "  ✓ Exists:  $dir"
    fi
done

# Ensure current user owns these directories so containers don't fail as root
chown -R $(id -u):$(id -g) "$PROJECT_ROOT/compose"
chown -R $(id -u):$(id -g) "$PROJECT_ROOT/projects"
chown -R $(id -u):$(id -g) "$PROJECT_ROOT/agents"
echo "  ✓ Ownership set to $(id -u):$(id -g)"

# ==========================================
# PHASE 3b: Special Permission Requirements
# ==========================================
echo -e "\n${YELLOW}[3b/6] Setting Special Permissions...${NC}"

# Traefik acme.json must be 600 or Traefik will fail
TRAEFIK_ACME="$PROJECT_ROOT/compose/network/traefik/data/acme.json"
if [ -f "$TRAEFIK_ACME" ]; then
    chmod 600 "$TRAEFIK_ACME"
    echo "  ✓ Traefik acme.json secured (600)"
else
    # Create empty acme.json with correct permissions
    touch "$TRAEFIK_ACME"
    chmod 600 "$TRAEFIK_ACME"
    echo "  ✓ Created empty Traefik acme.json (600)"
fi

# PostgreSQL data directory should be owned by postgres user (UID 999)
POSTGRES_DATA="$PROJECT_ROOT/compose/data/postgres/data"
if [ -d "$POSTGRES_DATA" ]; then
    # Check if directory is empty (fresh install) or has data
    if [ -z "$(ls -A "$POSTGRES_DATA" 2>/dev/null)" ]; then
        chown 999:999 "$POSTGRES_DATA"
        echo "  ✓ PostgreSQL data directory owned by postgres (999:999)"
    else
        echo "  ⚠ PostgreSQL data exists, skipping ownership change (preserve existing data)"
    fi
fi

# SSH keys for hermes-agent (if they exist)
SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_KNOWN="$HOME/.ssh/known_hosts"
if [ -f "$SSH_KEY" ]; then
    chmod 600 "$SSH_KEY"
    echo "  ✓ SSH private key secured (600)"
fi
if [ -f "$SSH_KNOWN" ]; then
    chmod 644 "$SSH_KNOWN"
    echo "  ✓ SSH known_hosts secured (644)"
fi

# ==========================================
# PHASE 4: Terraform Base Infrastructure
# ==========================================
echo -e "\n${YELLOW}[4/6] Applying Terraform Infrastructure...${NC}"
cd "$PROJECT_ROOT/terraform"

# Check if terraform.tfstate exists (existing infrastructure)
if [ -f "terraform.tfstate" ]; then
    echo "  ✓ Existing Terraform state found, will update"
else
    echo "  ✓ Fresh Terraform state, will create infrastructure"
fi

terraform init -upgrade -input=false
terraform validate

# Plan and apply automatically
echo "  Planning infrastructure changes..."
terraform plan -out=bootstrap.tfplan -input=false

# Apply with auto-approve
echo "  Applying infrastructure..."
terraform apply -auto-approve -input=false bootstrap.tfplan
rm -f bootstrap.tfplan

cd "$PROJECT_ROOT"
echo "  ✓ Terraform infrastructure ready"

# ==========================================
# PHASE 5: Docker Compose Profile Detection
# ==========================================
echo -e "\n${YELLOW}[5/6] Detecting Docker Compose Profiles...${NC}"

# Read enabled profiles from terraform output or .env
PROFILES=()

# Check if .env has COMPOSE_PROFILES defined
if [ -f "$PROJECT_ROOT/.env" ] && grep -q "^COMPOSE_PROFILES=" "$PROJECT_ROOT/.env"; then
    PROFILES_STRING=$(grep "^COMPOSE_PROFILES=" "$PROJECT_ROOT/.env" | cut -d'=' -f2-)
    IFS=',' read -ra PROFILES <<< "$PROFILES_STRING"
    echo "  ✓ Profiles from .env: ${PROFILES[*]}"
else
    # Default profiles from terraform/variables.tf
    PROFILES=("ai" "security" "monitoring" "management" "ci" "productivity" "network")
    echo "  ✓ Using default profiles: ${PROFILES[*]}"
fi

# Build docker compose command with profiles
COMPOSE_CMD="docker compose"
for profile in "${PROFILES[@]}"; do
    COMPOSE_CMD="$COMPOSE_CMD --profile $profile"
done

echo "  ✓ Compose command: $COMPOSE_CMD"

# ==========================================
# PHASE 6: Docker Stack Deployment
# ==========================================
echo -e "\n${YELLOW}[6/6] Launching Docker Orchestration...${NC}"

# Pull images first (optional, but faster)
echo "  Pulling latest images..."
$COMPOSE_CMD pull --quiet || echo "  ⚠ Some images failed to pull, will build locally"

# Start the stack
echo "  Starting services..."
$COMPOSE_CMD up -d --remove-orphans --wait --wait-timeout 120

echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN}Bootstrap Complete! Stack is initializing.${NC}"
echo -e "${GREEN}=============================================${NC}"

# ==========================================
# POST-BOOTSTRAP: Health Checks
# ==========================================
echo -e "\n${BLUE}Running health checks...${NC}"

# Wait a bit for services to stabilize
sleep 5

# Check critical services
CRITICAL_SERVICES=("postgres" "redis" "traefik" "litellm" "hermes-agent")
ALL_HEALTHY=true

for service in "${CRITICAL_SERVICES[@]}"; do
    STATUS=$(docker ps --format "{{.Status}}" --filter "name=^${service}$" 2>/dev/null | head -1)
    if [[ "$STATUS" == *"healthy"* ]]; then
        echo "  ✓ $service: healthy"
    elif [[ "$STATUS" == *"Up"* ]]; then
        echo "  ⚠ $service: running (not yet healthy)"
    else
        echo "  ✗ $service: not running"
        ALL_HEALTHY=false
    fi
done

if [ "$ALL_HEALTHY" = true ]; then
    echo -e "\n${GREEN}✓ All critical services are healthy!${NC}"
else
    echo -e "\n${YELLOW}⚠ Some services are still initializing. Check with: docker compose ps${NC}"
fi

echo -e "\n${BLUE}Next steps:${NC}"
echo "  1. Check logs: docker compose logs -f"
echo "  2. View status: docker compose ps"
echo "  3. Access services via Traefik dashboard: https://traefik.${DOMAIN:-wazzan.us}"
