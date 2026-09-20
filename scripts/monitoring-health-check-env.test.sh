#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$(mktemp)"
MISSING_ENV_OUTPUT="$(mktemp)"
LOG_FILE="$(mktemp)"
ERROR_LOG="$(mktemp)"
trap 'rm -f "$ENV_FILE" "$MISSING_ENV_OUTPUT" "$LOG_FILE" "$ERROR_LOG"' EXIT

cat > "$ENV_FILE" <<'EOF'
export AIRTABLE_API_KEY="test-key"
export AIRTABLE_BASE_ID="app1234567890ABCD"
export AIRTABLE_HEALTHCHECK_TABLE="Env File Table"
export MAKE_HEALTHCHECK_URL="https://hook.make.com/env-file/token"
EOF

output="$("$REPO_ROOT/scripts/monitoring-health-check.sh" --env-file "$ENV_FILE" --dry-run)"

case "$output" in
    *"Would probe Make.com endpoint: https://hook.make.com"* ) : ;;
    * ) echo "Expected dry-run output to redact MAKE_HEALTHCHECK_URL to scheme and host" >&2; exit 1 ;;
esac

case "$output" in
    *"/env-file/token"* ) echo "Expected dry-run output to redact the MAKE_HEALTHCHECK_URL path" >&2; exit 1 ;;
    * ) : ;;
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

missing_env_file="${ENV_FILE}.missing"
if "$REPO_ROOT/scripts/monitoring-health-check.sh" --env-file "$missing_env_file" --dry-run >"$MISSING_ENV_OUTPUT" 2>&1; then
    echo "Expected missing --env-file to fail" >&2
    exit 1
fi

case "$(cat "$MISSING_ENV_OUTPUT")" in
    *"Monitoring env file not found: $missing_env_file"* ) : ;;
    * ) echo "Expected missing env-file error message" >&2; exit 1 ;;
esac

source "$REPO_ROOT/scripts/monitoring-health-check.sh"

curl() {
    printf '%s' "200"
}

live_output="$(MONITORING_ENV_FILE="$ENV_FILE" main --env-file "$ENV_FILE")"

case "$live_output" in
    *"Make.com endpoint reachable (200)"* ) : ;;
    * ) echo "Expected live env-file path to exercise Make.com success" >&2; exit 1 ;;
esac

case "$live_output" in
    *"Airtable table read succeeded (200)"* ) : ;;
    * ) echo "Expected live env-file path to exercise Airtable success" >&2; exit 1 ;;
esac
