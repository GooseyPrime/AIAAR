#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$(mktemp)"
trap 'rm -f "$ENV_FILE"' EXIT

cat > "$ENV_FILE" <<'EOF'
export AIRTABLE_API_KEY="test-key"
export AIRTABLE_BASE_ID="appEnvFileBase"
export AIRTABLE_HEALTHCHECK_TABLE="Env File Table"
export MAKE_HEALTHCHECK_URL="https://hook.make.com/env-file"
EOF

output="$("$REPO_ROOT/scripts/monitoring-health-check.sh" --env-file "$ENV_FILE" --dry-run)"

case "$output" in
    *"Would probe Make.com endpoint: https://hook.make.com/env-file"* ) : ;;
    * ) echo "Expected env-file override to set MAKE_HEALTHCHECK_URL" >&2; exit 1 ;;
esac

case "$output" in
    *"Airtable probe table: Env File Table"* ) : ;;
    * ) echo "Expected env-file override to set AIRTABLE_HEALTHCHECK_TABLE" >&2; exit 1 ;;
esac

case "$output" in
    *"Environment file: $ENV_FILE"* ) : ;;
    * ) echo "Expected dry-run to report the active env file path" >&2; exit 1 ;;
esac

echo "monitoring-health-check env-file test passed"
