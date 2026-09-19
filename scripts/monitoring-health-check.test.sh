#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$(mktemp)"
ERROR_LOG="$(mktemp)"
trap 'rm -f "$LOG_FILE" "$ERROR_LOG"' EXIT

source "$REPO_ROOT/scripts/monitoring-health-check.sh"

assert_success() {
    if ! "$@"; then
        echo "Expected success: $*" >&2
        exit 1
    fi
}

assert_failure() {
    if "$@"; then
        echo "Expected failure: $*" >&2
        exit 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        echo "Expected output to contain: $needle" >&2
        echo "Actual output: $haystack" >&2
        exit 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo "Expected output to not contain: $needle" >&2
        echo "Actual output: $haystack" >&2
        exit 1
    fi
}

curl() {
    printf '%s' "${MOCK_CURL_HTTP_CODE:?}"
}

test_make_host_fallback_accepts_redirect() {
    local output
    MOCK_CURL_HTTP_CODE="302"
    output="$(check_make_endpoint "https://hook.make.com" "host-fallback")"
    assert_contains "$output" "Make.com host reachable (302)"
}

test_make_host_fallback_accepts_non_5xx_and_rejects_5xx() {
    local output
    MOCK_CURL_HTTP_CODE="204"
    output="$(check_make_endpoint "https://hook.make.com" "host-fallback")"
    assert_contains "$output" "Make.com host reachable (204)"

    MOCK_CURL_HTTP_CODE="301"
    output="$(check_make_endpoint "https://hook.make.com" "host-fallback")"
    assert_contains "$output" "Make.com host reachable (301)"

    MOCK_CURL_HTTP_CODE="304"
    output="$(check_make_endpoint "https://hook.make.com" "host-fallback")"
    assert_contains "$output" "Make.com host reachable (304)"

    MOCK_CURL_HTTP_CODE="404"
    output="$(check_make_endpoint "https://hook.make.com" "host-fallback")"
    assert_contains "$output" "Make.com host reachable (404)"

    MOCK_CURL_HTTP_CODE="500"
    assert_failure check_make_endpoint "https://hook.make.com" "host-fallback"
}

test_make_explicit_endpoint_requires_200() {
    local output
    MOCK_CURL_HTTP_CODE="200"
    output="$(check_make_endpoint "https://hook.make.com/endpoint" "explicit-endpoint")"
    assert_contains "$output" "Make.com endpoint reachable (200)"

    MOCK_CURL_HTTP_CODE="302"
    assert_failure check_make_endpoint "https://hook.make.com/endpoint" "explicit-endpoint"
}

test_make_endpoint_failure_redacts_logged_url() {
    local log_output

    : > "$ERROR_LOG"
    MOCK_CURL_HTTP_CODE="000"
    assert_failure check_make_endpoint "https://hook.make.com/secret/token" "explicit-endpoint"
    log_output="$(cat "$ERROR_LOG")"
    assert_contains "$log_output" "https://hook.make.com"
    assert_not_contains "$log_output" "/secret/token"
}

test_airtable_status_branches() {
    local output

    AIRTABLE_API_KEY="test-key"

    MOCK_CURL_HTTP_CODE="200"
    output="$(check_airtable_endpoint "https://api.airtable.com/v0/app/table" "Target Items")"
    assert_contains "$output" "Airtable table read succeeded (200)"

    MOCK_CURL_HTTP_CODE="401"
    assert_failure check_airtable_endpoint "https://api.airtable.com/v0/app/table" "Target Items"

    MOCK_CURL_HTTP_CODE="404"
    assert_failure check_airtable_endpoint "https://api.airtable.com/v0/app/table" "Target Items"
}

test_env_loader_accepts_export_and_ignores_unlisted_keys() {
    local env_file
    env_file="$(mktemp)"
    trap 'rm -f "$env_file"' RETURN

    cat > "$env_file" <<'EOF'
export AIRTABLE_API_KEY = test-key
export PATH = /not/used
MAKE_WEBHOOK_BASE_URL = https://hook.make.com
EOF

    unset AIRTABLE_API_KEY MAKE_WEBHOOK_BASE_URL
    load_env_file "$env_file"

    [ "${AIRTABLE_API_KEY}" = "test-key" ]
    [ "${MAKE_WEBHOOK_BASE_URL}" = "https://hook.make.com" ]
}

test_env_loader_preserves_hash_inside_quotes() {
    local env_file
    env_file="$(mktemp)"
    trap 'rm -f "$env_file"' RETURN

    cat > "$env_file" <<'EOF'
AIRTABLE_HEALTHCHECK_TABLE="Target #1" # keep quoted hash, strip trailing comment
MAKE_HEALTHCHECK_URL="https://hook.make.com/path#fragment"
EOF

    unset AIRTABLE_HEALTHCHECK_TABLE MAKE_HEALTHCHECK_URL
    load_env_file "$env_file"

    [ "${AIRTABLE_HEALTHCHECK_TABLE}" = "Target #1" ]
    [ "${MAKE_HEALTHCHECK_URL}" = "https://hook.make.com/path#fragment" ]
}

test_env_loader_preserves_existing_environment_values() {
    local env_file
    env_file="$(mktemp)"
    trap 'rm -f "$env_file"' RETURN

    cat > "$env_file" <<'EOF'
AIRTABLE_API_KEY=file-key
MAKE_WEBHOOK_BASE_URL=https://hook.make.com/file
EOF

    AIRTABLE_API_KEY="shell-key"
    MAKE_WEBHOOK_BASE_URL="https://hook.make.com/shell"
    load_env_file "$env_file"

    [ "${AIRTABLE_API_KEY}" = "shell-key" ]
    [ "${MAKE_WEBHOOK_BASE_URL}" = "https://hook.make.com/shell" ]
}

test_env_loader_ignores_cli_control_keys() {
    local env_file
    env_file="$(mktemp)"
    trap 'rm -f "$env_file"' RETURN

    cat > "$env_file" <<'EOF'
DRY_RUN=false
TIMEOUT=999
MAKE_HEALTHCHECK_URL=https://hook.make.com/health
EOF

    unset MAKE_HEALTHCHECK_URL
    DRY_RUN=true
    TIMEOUT=7
    load_env_file "$env_file"

    [ "$DRY_RUN" = true ]
    [ "$TIMEOUT" = "7" ]
    [ "${MAKE_HEALTHCHECK_URL}" = "https://hook.make.com/health" ]
}

test_timeout_argument_validation() {
    local output
    local status

    output="$("$REPO_ROOT/scripts/monitoring-health-check.sh" --dry-run --timeout 7)"
    assert_contains "$output" "Timeout: 7s"

    set +e
    output="$("$REPO_ROOT/scripts/monitoring-health-check.sh" --timeout nope 2>&1)"
    status=$?
    set -e
    [ "$status" -ne 0 ]
    assert_contains "$output" "--timeout must be a positive integer number of seconds."

    set +e
    output="$("$REPO_ROOT/scripts/monitoring-health-check.sh" --timeout 00 2>&1)"
    status=$?
    set -e
    [ "$status" -ne 0 ]
    assert_contains "$output" "--timeout must be a positive integer number of seconds."
}

test_airtable_base_id_validation() {
    assert_success is_valid_airtable_base_id "app1234567890ABCD"
    assert_failure is_valid_airtable_base_id "<base-id-redacted>"
    assert_failure is_valid_airtable_base_id "app1"
    assert_failure is_valid_airtable_base_id "base123"
}

test_url_encode_uses_utf8_bytes() {
    local encoded

    encoded="$(url_encode "Café ☕")"
    [ "$encoded" = "Caf%C3%A9%20%E2%98%95" ]
}

test_make_host_fallback_accepts_redirect
test_make_host_fallback_accepts_non_5xx_and_rejects_5xx
test_make_explicit_endpoint_requires_200
test_make_endpoint_failure_redacts_logged_url
test_airtable_status_branches
test_env_loader_accepts_export_and_ignores_unlisted_keys
test_env_loader_preserves_hash_inside_quotes
test_env_loader_preserves_existing_environment_values
test_env_loader_ignores_cli_control_keys
test_timeout_argument_validation
test_airtable_base_id_validation
test_url_encode_uses_utf8_bytes

echo "monitoring-health-check tests passed"
