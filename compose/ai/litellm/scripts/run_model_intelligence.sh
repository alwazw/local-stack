#!/bin/bash
# ===================================================================
# Model Intelligence Gatherer — Entry Point
# Runs the Python model aggregation script and outputs reports
# to the LiteLLM config intelligence directory.
#
# Usage:
#   ./run_model_intelligence.sh [--dry-run] [--summary]
#
# Environment variables (same as litellm container):
#   OPENROUTER_KEY_1, OPENROUTER_KEY_2, OPENROUTER_KEY_3
#   GEMINI_API_KEY_1, GEMINI_API_KEY_2, GEMINI_API_KEY_3
#   GROQ_API_KEY_1, GROQ_API_KEY_2
#   NOVITA_API_KEY_1
#   NVIDIA_NIM_KEY_1
#   ALIBABA_MODELSTUDIO_KEY_1, ALIBABA_MODELSTUDIO_KEY_2
# ===================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LITELLM_CONFIG_DIR="/app/config"
REPORT_BASE="${LITELLM_CONFIG_DIR}/intelligence_reports"
DATE_STAMP=$(date -u +%Y-%m-%d)
OUTPUT_DIR="${REPORT_BASE}/${DATE_STAMP}"
DRY_RUN=false
SUMMARY=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --summary)  SUMMARY=true ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--summary]"
      echo "  --dry-run  Print what would be done without executing"
      echo "  --summary  Print a quick summary of findings"
      exit 0
      ;;
  esac
done

# Output directory on host (mounted volume)
HOST_REPORT_DIR="/mnt/d/docker/compose/ai/litellm/config/intelligence_reports/${DATE_STAMP}"

if [ "$DRY_RUN" = true ]; then
  echo "[DRY RUN] Would create: ${HOST_REPORT_DIR}"
  echo "[DRY RUN] Would run: python3 ${SCRIPT_DIR}/model_intelligence_gatherer.py"
  echo "[DRY RUN] Would output:"
  echo "  - models_intelligence_report.md"
  echo "  - models_intelligence.json"
  echo "  - missed_opportunities.md"
  echo "  - litellm_model_suggestions.yml"
  exit 0
fi

# Check for Python
if ! command -v python3 &>/dev/null; then
  echo "[ERROR] python3 not found. Install with: apt-get install -y python3"
  exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR" 2>/dev/null || mkdir -p "$HOST_REPORT_DIR"

echo "============================================"
echo "🧠 Model Intelligence Gatherer"
echo "============================================"
echo "Output: ${OUTPUT_DIR}"
echo ""

# Run the gatherer
cd "$SCRIPT_DIR"
python3 model_intelligence_gatherer.py

# Copy reports to host-mounted directory if running in container
if [ "$OUTPUT_DIR" != "$HOST_REPORT_DIR" ] && [ -d "/mnt/d/docker" ]; then
  mkdir -p "$HOST_REPORT_DIR"
  cp -v "${OUTPUT_DIR}"/* "$HOST_REPORT_DIR/" 2>/dev/null || true
  echo ""
  echo "[INFO] Reports copied to host: ${HOST_REPORT_DIR}"
fi

# Summary
if [ "$SUMMARY" = true ] && [ -f "${HOST_REPORT_DIR}/models_intelligence.json" ]; then
  echo ""
  echo "============================================"
  echo "📊 Summary"
  echo "============================================"
  python3 -c "
import json
with open('${HOST_REPORT_DIR}/models_intelligence.json') as f:
    d = json.load(f)
print(f'Total models:    {d[\"total_models\"]}')
print(f'Free models:     {d[\"free_models\"]}')
print(f'By provider:')
for prov, models in sorted(d['by_provider'].items()):
    print(f'  {prov}: {len(models)}')
print(f'By tier:')
for tier, models in sorted(d['by_tier'].items()):
    print(f'  {tier}: {len(models)}')
"
fi

echo ""
echo "✅ Done. Reports in: ${HOST_REPORT_DIR:-$OUTPUT_DIR}"
