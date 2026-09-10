#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/scripts/monitoring-health-check.sh"

LOG_FILE="/tmp/monitoring-health-check-test.log"
ERROR_LOG="/tmp/monitoring-health-check-test-errors.log"

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

curl() {
    printf '%s' "${MOCK_CURL_HTTP_CODE:?}"
}

test_make_host_fallback_accepts_redirect() {
    local output
    MOCK_CURL_HTTP_CODE="302"
    output="$(check_make_endpoint "https://hook.make.com" "host-fallback")"
    assert_contains "$output" "Make.com host reachable (302)"
}

test_make_host_fallback_rejects_server_error() {
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
export AIRTABLE_API_KEY=test-key
export PATH=/not/used
MAKE_WEBHOOK_BASE_URL=https://hook.make.com
EOF

    unset AIRTABLE_API_KEY MAKE_WEBHOOK_BASE_URL
    load_env_file "$env_file"

    [ "${AIRTABLE_API_KEY}" = "test-key" ]
    [ "${MAKE_WEBHOOK_BASE_URL}" = "https://hook.make.com" ]
}

test_make_host_fallback_accepts_redirect
test_make_host_fallback_rejects_server_error
test_make_explicit_endpoint_requires_200
test_airtable_status_branches
test_env_loader_accepts_export_and_ignores_unlisted_keys

echo "monitoring-health-check tests passed"
