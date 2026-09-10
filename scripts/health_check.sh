#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SCRIPT="${SETUP_SCRIPT:-$SCRIPT_DIR/setup.sh}"
SCENARIO_VALIDATOR="${SCENARIO_VALIDATOR:-$SCRIPT_DIR/validate_scenarios.py}"
SCENARIO_DIR="${SCENARIO_DIR:-$REPO_ROOT/make-scenarios}"

echo "🔎 AIAAR health check"
echo "===================="

echo "• Verifying setup dry run"
bash "$SETUP_SCRIPT" --dry-run

if [ ! -d "$SCENARIO_DIR" ]; then
    echo "❌ Missing Make.com scenario directory: $SCENARIO_DIR" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ python3 is required to validate Make.com scenario definitions" >&2
    exit 1
fi

scenario_files=()
while IFS= read -r -d '' scenario_file; do
    scenario_files+=("$scenario_file")
done < <(find "$SCENARIO_DIR" -maxdepth 1 -type f -name '*.json' -print0)

if [ "${#scenario_files[@]}" -eq 0 ]; then
    echo "❌ No Make.com scenario definitions found in $SCENARIO_DIR" >&2
    exit 1
fi

echo "• Validating ${#scenario_files[@]} Make.com scenario definition(s)"
python3 "$SCENARIO_VALIDATOR" --require-webhooks "${scenario_files[@]}"

echo "✅ Health check completed successfully"
