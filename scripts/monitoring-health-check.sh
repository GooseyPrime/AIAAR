#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
LOG_DIR="$REPO_ROOT/logs"
LOG_FILE="$LOG_DIR/monitoring-health-check.log"
ERROR_LOG="$LOG_DIR/monitoring-health-check_errors.log"
DRY_RUN=false
TIMEOUT=10

mkdir -p "$LOG_DIR"

log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [ERROR] $message" | tee -a "$ERROR_LOG" >&2
}

trim_whitespace() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

strip_inline_comment() {
    local value="${1:-}"
    local output=""
    local quote=""
    local char
    local previous_char=""
    local i

    for ((i=0; i<${#value}; i++)); do
        char="${value:i:1}"

        if [ -z "$quote" ]; then
            if [ "$char" = "#" ] && { [ "$i" -eq 0 ] || [[ "$previous_char" =~ [[:space:]] ]]; }; then
                break
            fi

            if [ "$char" = "\"" ] || [ "$char" = "'" ]; then
                quote="$char"
            fi
        elif [ "$char" = "$quote" ]; then
            quote=""
        fi

        output+="$char"
        previous_char="$char"
    done

    trim_whitespace "$output"
}

strip_wrapping_quotes() {
    local value="${1:-}"
    local first_char
    local last_char

    if [ "${#value}" -ge 2 ]; then
        first_char="${value:0:1}"
        last_char="${value: -1}"

        if { [ "$first_char" = "\"" ] && [ "$last_char" = "\"" ]; } || { [ "$first_char" = "'" ] && [ "$last_char" = "'" ]; }; then
            value="${value:1:${#value}-2}"
        fi
    fi

    printf '%s' "$value"
}

load_env_file() {
    local env_file="$1"
    local line
    local key
    local value

    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "${line// }" ] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        key="${line%%=*}"
        if [ "$key" = "$line" ]; then
            continue
        fi

        value="${line#*=}"
        key="$(trim_whitespace "$key")"
        key="${key#export }"
        key="$(trim_whitespace "$key")"
        value="$(trim_whitespace "${value:-}")"
        value="$(strip_inline_comment "$value")"
        value="$(strip_wrapping_quotes "$value")"

        if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            log_error "Invalid environment variable name in $env_file: $key"
            exit 1
        fi

        declare -gx "$key=$value"
    done < "$env_file"
}

usage() {
    cat <<EOF
Usage: ./scripts/monitoring-health-check.sh [--dry-run] [--timeout SECONDS]
EOF
}

is_placeholder_value() {
    case "${1:-}" in
        ""|YOUR_*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

url_encode() {
    local value="${1:-}"

    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
        return
    fi

    if command -v python >/dev/null 2>&1; then
        python -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
        return
    fi

    log_error "python3 or python is required to URL-encode Airtable table names"
    exit 1
}

check_make_endpoint() {
    local url="$1"
    local probe_mode="$2"
    local http_code

    http_code=$(curl -sS --max-time "$TIMEOUT" -o /dev/null -w "%{http_code}" "$url" || true)
    if [ "$probe_mode" = "host-fallback" ] && [[ "$http_code" =~ ^[1-5][0-9]{2}$ ]]; then
        echo "✅ Make.com host reachable ($http_code)"
        log_message "INFO" "Make.com host reachable with HTTP $http_code"
        return 0
    fi

    if [ "$probe_mode" = "explicit-endpoint" ] && [ "$http_code" = "200" ]; then
        echo "✅ Make.com endpoint reachable ($http_code)"
        log_message "INFO" "Make.com endpoint reachable with HTTP $http_code"
        return 0
    fi

    log_error "Make.com endpoint check failed for $url with HTTP ${http_code:-000}"
    return 1
}

check_airtable_endpoint() {
    local url="$1"
    local table_name="$2"
    local http_code
    local auth_header_name="Authorization"
    local auth_header_value="Bearer ${AIRTABLE_API_KEY}"

    http_code=$(curl -sS --max-time "$TIMEOUT" -o /dev/null -w "%{http_code}" \
        -H "${auth_header_name}: ${auth_header_value}" \
        "$url" || true)

    if [ "$http_code" = "200" ]; then
        echo "✅ Airtable table read succeeded ($http_code)"
        log_message "INFO" "Airtable table read succeeded with HTTP $http_code"
        return 0
    fi

    if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        log_error "Airtable auth or permission check failed for the configured probe table ($table_name) with HTTP $http_code"
    elif [ "$http_code" = "404" ] || [ "$http_code" = "422" ]; then
        log_error "Airtable API check failed for the configured probe table ($table_name) with HTTP $http_code"
    else
        log_error "Airtable API check failed for $url with HTTP ${http_code:-000}"
    fi
    return 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --timeout)
            if [ "$#" -lt 2 ]; then
                usage
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -le 0 ]; then
                echo "❌ --timeout must be a positive integer number of seconds." >&2
                exit 1
            fi
            TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ -f "$ENV_FILE" ]; then
    load_env_file "$ENV_FILE"
fi

make_url="${MAKE_HEALTHCHECK_URL:-${MAKE_WEBHOOK_BASE_URL:-https://hook.make.com}}"
make_probe_mode="host-fallback"
if [ -n "${MAKE_HEALTHCHECK_URL:-}" ]; then
    make_probe_mode="explicit-endpoint"
fi
airtable_table="${AIRTABLE_HEALTHCHECK_TABLE:-Target Items}"
airtable_table_encoded="$(url_encode "$airtable_table")"
airtable_url="https://api.airtable.com/v0/${AIRTABLE_BASE_ID:-YOUR_AIRTABLE_BASE_ID}/${airtable_table_encoded}?maxRecords=1"
airtable_url_preview="https://api.airtable.com/v0/<base-id-redacted>/${airtable_table_encoded}?maxRecords=1"

echo "📡 AIAAR production monitoring health check"
echo "=========================================="

if [ "$DRY_RUN" = true ]; then
    echo "🧪 Dry run only - no live API calls will be made."
    echo "Would probe Make.com endpoint: $make_url"
    if [ -z "${MAKE_HEALTHCHECK_URL:-}" ]; then
        echo "Make.com probe mode: host-level fallback via MAKE_WEBHOOK_BASE_URL"
    else
        echo "Make.com probe mode: explicit endpoint via MAKE_HEALTHCHECK_URL"
    fi
    echo "Would probe Airtable endpoint: $airtable_url_preview"
    echo "Airtable probe table: $airtable_table"
    echo "Timeout: ${TIMEOUT}s"
    exit 0
fi

if is_placeholder_value "${AIRTABLE_API_KEY:-}" || is_placeholder_value "${AIRTABLE_BASE_ID:-}"; then
    log_error "AIRTABLE_API_KEY and AIRTABLE_BASE_ID must be set before running live checks"
    echo "❌ Set AIRTABLE_API_KEY and AIRTABLE_BASE_ID in .env or the current shell." >&2
    exit 1
fi

if [ -z "${airtable_table}" ]; then
    log_error "AIRTABLE_HEALTHCHECK_TABLE must reference an existing Airtable table"
    echo "❌ Set AIRTABLE_HEALTHCHECK_TABLE to an existing Airtable table name." >&2
    exit 1
fi

log_message "INFO" "Starting monitoring health check"
check_make_endpoint "$make_url" "$make_probe_mode"
check_airtable_endpoint "$airtable_url" "$airtable_table"
log_message "INFO" "Monitoring health check completed successfully"
