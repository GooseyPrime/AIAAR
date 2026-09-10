#!/bin/bash

# AIAAR Setup Script
# Automated setup for Airtable database and basic configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/config/environment.yml"
CONFIG_TEMPLATE="$REPO_ROOT/config/environment.example.yml"
ENV_FILE="$REPO_ROOT/.env"
ENV_TEMPLATE="$REPO_ROOT/.env.example"
LOG_DIR="$REPO_ROOT/logs"
LOG_FILE="$LOG_DIR/setup.log"
ERROR_LOG="$LOG_DIR/setup_errors.log"
STATUS_FILE="$REPO_ROOT/.setup_status"
DRY_RUN=false

mkdir -p "$LOG_DIR"
cd "$REPO_ROOT"

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

log_env_status() {
    local var_name="$1"
    if [ -n "${!var_name:-}" ]; then
        printf '%s=present' "$var_name"
    else
        printf '%s=missing' "$var_name"
    fi
}

error_handler() {
    trap - ERR
    set +e

    local line_number="${1:-unknown}"
    local error_code="${2:-1}"
    local command="${3:-unknown}"

    log_error "Script failed at line $line_number with exit code $error_code"
    log_error "Failed command: $command"
    log_error "Repository root: $REPO_ROOT"
    log_error "Environment status: $(log_env_status AIRTABLE_API_KEY), $(log_env_status AIRTABLE_BASE_ID), $(log_env_status EBAY_CLIENT_ID), $(log_env_status OPENAI_API_KEY)"
    echo "❌ Setup failed. Check error logs at $ERROR_LOG for details." >&2
    exit "$error_code"
}

trap 'error_handler ${LINENO} $? "$BASH_COMMAND"' ERR

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
        value="$(trim_whitespace "${value:-}")"
        value="$(strip_inline_comment "$value")"
        if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            log_error "Invalid environment variable name in $env_file: $key"
            exit 1
        fi

        value="$(strip_wrapping_quotes "$value")"
        declare -gx "$key=$value"
    done < "$env_file"
}

set_if_unset() {
    local var_name="$1"
    local value="$2"

    if [ -z "${!var_name:-}" ] || is_placeholder_value "${!var_name}"; then
        declare -gx "$var_name=$value"
    fi
}

assert_no_newlines() {
    local var_name="$1"
    local value=""

    if [ -z "${!var_name+x}" ]; then
        return
    fi

    value="${!var_name}"

    case "$value" in
        *$'\n'*|*$'\r'*)
            log_error "Invalid newline detected in $var_name"
            exit 1
            ;;
    esac
}

response_body() {
    printf '%s\n' "$1" | sed '$d'
}

response_http_code() {
    printf '%s\n' "$1" | sed -n '$p'
}

ensure_http_code() {
    local http_code="$1"
    local context="$2"

    if ! [[ "$http_code" =~ ^[0-9]{3}$ ]]; then
        log_error "$context returned invalid HTTP status: ${http_code:-missing}"
        exit 1
    fi
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

fetch_ebay_auth_token() {
    local basic_auth
    local token_response
    local http_code
    local access_token

    if ! basic_auth=$(printf '%s:%s' "$EBAY_CLIENT_ID" "$EBAY_CLIENT_SECRET" | base64 | tr -d '\n'); then
        log_error "Failed to encode eBay client credentials"
        exit 1
    fi

    if ! token_response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: Basic $basic_auth" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials&scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope" \
        "https://api.ebay.com/identity/v1/oauth2/token" 2>/dev/null); then
        log_error "Failed to obtain eBay access token"
        exit 1
    fi

    http_code=$(response_http_code "$token_response")
    ensure_http_code "$http_code" "eBay token request"
    if [ "$http_code" != "200" ]; then
        log_error "eBay token request failed with HTTP $http_code"
        exit 1
    fi

    access_token=$(response_body "$token_response" | jq -r '.access_token' 2>/dev/null)
    if [ -z "$access_token" ] || [ "$access_token" = "null" ]; then
        log_error "Failed to parse eBay access token"
        exit 1
    fi

    printf '%s' "$access_token"
}

yaml_value() {
    local section="$1"
    local key="$2"
    local file="$3"

    awk -v section="$section" -v key="$key" '
        {
            match($0, /^[[:space:]]*/)
            indent = RLENGTH
            trimmed = $0
            sub(/^[[:space:]]+/, "", trimmed)

            if (trimmed == section ":") {
                in_section = 1
                section_indent = indent
                next
            }

            if (in_section && indent <= section_indent && trimmed != "" && trimmed !~ /^#/) {
                in_section = 0
            }

            if (in_section) {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                prefix = key ":"

                if (index(line, prefix) == 1) {
                    value = substr(line, length(prefix) + 1)
                    sub(/^[[:space:]]*/, "", value)
                    print value
                    exit
                }
            }
        }
    ' "$file"
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

populate_from_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return
    fi

    set_if_unset AIRTABLE_API_KEY "$(strip_wrapping_quotes "$(yaml_value airtable api_key "$CONFIG_FILE")")"
    set_if_unset AIRTABLE_BASE_ID "$(strip_wrapping_quotes "$(yaml_value airtable base_id "$CONFIG_FILE")")"
    set_if_unset EBAY_CLIENT_ID "$(strip_wrapping_quotes "$(yaml_value ebay client_id "$CONFIG_FILE")")"
    set_if_unset EBAY_CLIENT_SECRET "$(strip_wrapping_quotes "$(yaml_value ebay client_secret "$CONFIG_FILE")")"
    set_if_unset EBAY_AUTH_TOKEN "$(strip_wrapping_quotes "$(yaml_value ebay auth_token "$CONFIG_FILE")")"
    set_if_unset OPENAI_API_KEY "$(strip_wrapping_quotes "$(yaml_value openai api_key "$CONFIG_FILE")")"
    set_if_unset MAKE_WEBHOOK_BASE_URL "$(strip_wrapping_quotes "$(yaml_value make webhook_base_url "$CONFIG_FILE")")"

    export AIRTABLE_API_KEY AIRTABLE_BASE_ID EBAY_CLIENT_ID EBAY_CLIENT_SECRET EBAY_AUTH_TOKEN OPENAI_API_KEY MAKE_WEBHOOK_BASE_URL
}

print_dry_run() {
    echo "🧪 Dry run only - no live API calls will be made."
    echo "Would validate:"
    echo "  - Airtable credentials and base access"
    echo "  - eBay API credentials"
    echo "  - OpenAI API credentials"
    echo "  - Airtable test record creation and cleanup"
    echo "  - local directories: logs/, backups/, temp/"

    if [ -f "$ENV_FILE" ] || [ -f "$CONFIG_FILE" ]; then
        echo "Configuration sources detected:"
        [ -f "$ENV_FILE" ] && echo "  - .env"
        [ -f "$CONFIG_FILE" ] && echo "  - config/environment.yml"
    else
        echo "No credentials found. Copy .env.example to .env for API keys and, if needed, config/environment.example.yml to config/environment.yml for local non-secret overrides."
    fi
}

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            echo "❌ Unknown argument: $arg"
            echo "Usage: ./scripts/setup.sh [--dry-run]"
            exit 1
            ;;
    esac
done

echo "🚀 AIAAR Setup Script"
echo "===================="
log_message "INFO" "AIAAR Setup Script started"

if [ -f "$ENV_FILE" ]; then
    echo "📖 Loading .env"
    log_message "INFO" "Loading configuration from .env"
    load_env_file "$ENV_FILE"
fi

if [ -f "$CONFIG_FILE" ]; then
    echo "📖 Reading configuration from config/environment.yml"
    log_message "INFO" "Reading configuration from config/environment.yml"
    populate_from_config
fi

if [ "$DRY_RUN" = true ]; then
    log_message "INFO" "Running dry-run setup check"
    print_dry_run
    exit 0
fi

log_message "INFO" "Checking required dependencies"
if ! command -v curl >/dev/null 2>&1; then
    log_error "curl is required but not installed"
    echo "❌ curl is required but not installed. Aborting." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not installed"
    echo "❌ jq is required but not installed. Aborting." >&2
    exit 1
fi

log_message "INFO" "All required dependencies found"

initialized_env=false
initialized_config=false

if [ ! -f "$ENV_FILE" ]; then
    echo "📝 Creating environment configuration..."
    if [ ! -f "$ENV_TEMPLATE" ]; then
        log_error "Missing required example file: $ENV_TEMPLATE"
        echo "❌ Missing required example file: .env.example" >&2
        exit 1
    fi
    if ! cp "$ENV_TEMPLATE" "$ENV_FILE"; then
        log_error "Failed to copy .env example"
        exit 1
    fi
    initialized_env=true
fi

if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$CONFIG_TEMPLATE" ]; then
        if ! cp "$CONFIG_TEMPLATE" "$CONFIG_FILE"; then
            log_error "Failed to copy environment example"
            exit 1
        fi
        initialized_config=true
    else
        log_message "WARN" "Optional config example not found, skipping config/environment.yml initialization"
    fi
fi

if [ "$initialized_env" = true ] || [ "$initialized_config" = true ]; then
    log_message "WARN" "Initialized missing local configuration files from examples"
    if [ "$initialized_env" = true ]; then
        load_env_file "$ENV_FILE"
    fi
    echo "✅ Local environment files created:"
    [ "$initialized_env" = true ] && echo "   - .env from .env.example"
    [ "$initialized_config" = true ] && echo "   - config/environment.yml from config/environment.example.yml"
    if [ "$initialized_env" = true ] && [ "$initialized_config" = true ]; then
        echo "⚠️  Review .env for real API keys and config/environment.yml for local overrides before rerunning live setup."
        exit 1
    elif [ "$initialized_env" = true ]; then
        echo "⚠️  Review and replace placeholder API keys in .env before rerunning live setup."
        exit 1
    elif [ "$initialized_config" = true ]; then
        echo "ℹ️  Continuing with values already loaded from .env for this run."
    fi
fi

log_message "INFO" "Verifying required environment variables"
required_vars=("AIRTABLE_API_KEY" "AIRTABLE_BASE_ID" "OPENAI_API_KEY")
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ] || is_placeholder_value "${!var}"; then
        log_error "Required environment variable $var is not set to a real value"
        echo "❌ Required environment variable $var is not set to a real value"
        echo "Please update .env with your API keys, or config/environment.yml if you intentionally keep local credentials there"
        exit 1
    fi
    log_message "INFO" "Environment variable $var is set"
done

if [ -n "${EBAY_AUTH_TOKEN:-}" ] && ! is_placeholder_value "$EBAY_AUTH_TOKEN"; then
    log_message "INFO" "Using configured eBay auth token"
elif [ -n "${EBAY_CLIENT_ID:-}" ] && [ -n "${EBAY_CLIENT_SECRET:-}" ] && ! is_placeholder_value "$EBAY_CLIENT_ID" && ! is_placeholder_value "$EBAY_CLIENT_SECRET"; then
    log_message "INFO" "Using eBay client credentials to request an access token"
else
    log_error "Set a real EBAY_AUTH_TOKEN or non-placeholder EBAY_CLIENT_ID and EBAY_CLIENT_SECRET"
    echo "❌ Set EBAY_AUTH_TOKEN or both EBAY_CLIENT_ID and EBAY_CLIENT_SECRET to real values"
    echo "Please update .env with your eBay credentials, or config/environment.yml if you intentionally keep local credentials there"
    exit 1
fi

echo "✅ Configuration validated"
log_message "INFO" "All required environment variables validated"

assert_no_newlines AIRTABLE_API_KEY
assert_no_newlines OPENAI_API_KEY

if [ -n "${EBAY_AUTH_TOKEN:-}" ] && ! is_placeholder_value "$EBAY_AUTH_TOKEN"; then
    assert_no_newlines EBAY_AUTH_TOKEN
elif [ -n "${EBAY_CLIENT_ID:-}" ] && [ -n "${EBAY_CLIENT_SECRET:-}" ] && ! is_placeholder_value "$EBAY_CLIENT_ID" && ! is_placeholder_value "$EBAY_CLIENT_SECRET"; then
    assert_no_newlines EBAY_CLIENT_ID
    assert_no_newlines EBAY_CLIENT_SECRET
    log_message "INFO" "Requesting eBay access token from client credentials"
    EBAY_AUTH_TOKEN="$(fetch_ebay_auth_token)"
    export EBAY_AUTH_TOKEN
fi

auth_header_prefix="Authorization: Bearer"
airtable_auth_header="$auth_header_prefix $AIRTABLE_API_KEY"
ebay_auth_header="$auth_header_prefix $EBAY_AUTH_TOKEN"
openai_auth_header="$auth_header_prefix $OPENAI_API_KEY"

echo "🔗 Testing Airtable connection..."
log_message "INFO" "Testing Airtable API connection"

if ! airtable_response=$(curl -s -w "\n%{http_code}" \
    -H "$airtable_auth_header" \
    "https://api.airtable.com/v0/$AIRTABLE_BASE_ID/Target%20Items?maxRecords=1" 2>/dev/null); then
    log_error "curl command failed for Airtable API test"
    exit 1
fi

http_code=$(response_http_code "$airtable_response")
ensure_http_code "$http_code" "Airtable API"
log_message "INFO" "Airtable API responded with HTTP code: $http_code"

if [ "$http_code" -eq 200 ]; then
    echo "✅ Airtable connection successful"
    log_message "INFO" "Airtable connection test successful"
elif [ "$http_code" -eq 401 ]; then
    log_error "Airtable authentication failed (HTTP 401)"
    echo "❌ Airtable authentication failed. Check your API key."
    exit 1
elif [ "$http_code" -eq 404 ]; then
    log_error "Airtable base not found (HTTP 404)"
    echo "❌ Airtable base not found. Check your Base ID or create tables first."
    exit 1
else
    log_error "Airtable connection failed with HTTP $http_code"
    echo "❌ Airtable connection failed with HTTP $http_code"
    exit 1
fi

echo "🔗 Testing eBay API connection..."
log_message "INFO" "Testing eBay API connection"

if ! ebay_response=$(curl -s -w "\n%{http_code}" \
    -H "$ebay_auth_header" \
    -H "X-EBAY-C-MARKETPLACE-ID: EBAY_US" \
    "https://api.ebay.com/buy/browse/v1/item_summary/search?q=test&limit=1" 2>/dev/null); then
    log_error "curl command failed for eBay API test"
    exit 1
fi

http_code=$(response_http_code "$ebay_response")
ensure_http_code "$http_code" "eBay API"
log_message "INFO" "eBay API responded with HTTP code: $http_code"

if [ "$http_code" -eq 200 ]; then
    echo "✅ eBay API connection successful"
    log_message "INFO" "eBay API connection test successful"
elif [ "$http_code" -eq 401 ]; then
    log_error "eBay authentication failed (HTTP 401)"
    echo "❌ eBay authentication failed. Check your auth token."
    exit 1
else
    log_error "eBay API connection failed with HTTP $http_code"
    echo "❌ eBay API connection failed with HTTP $http_code"
    exit 1
fi

echo "🔗 Testing OpenAI API connection..."
log_message "INFO" "Testing OpenAI API connection"

if ! openai_response=$(curl -s -w "\n%{http_code}" \
    -H "$openai_auth_header" \
    "https://api.openai.com/v1/models" 2>/dev/null); then
    log_error "curl command failed for OpenAI API test"
    exit 1
fi

http_code=$(response_http_code "$openai_response")
ensure_http_code "$http_code" "OpenAI API"
log_message "INFO" "OpenAI API responded with HTTP code: $http_code"

if [ "$http_code" -eq 200 ]; then
    echo "✅ OpenAI API connection successful"
    log_message "INFO" "OpenAI API connection test successful"
elif [ "$http_code" -eq 401 ]; then
    log_error "OpenAI authentication failed (HTTP 401)"
    echo "❌ OpenAI authentication failed. Check your API key."
    exit 1
else
    log_error "OpenAI API connection failed with HTTP $http_code"
    echo "❌ OpenAI API connection failed with HTTP $http_code"
    exit 1
fi

echo "📊 Creating test data in Airtable..."
log_message "INFO" "Creating test data in Airtable"

test_item_id="TEST-ITEM-$(date +%s)-$$-$(awk 'BEGIN { srand(); printf \"%06d\", rand() * 1000000 }')"

test_item_data='{
    "fields": {
        "itemId": "'"$test_item_id"'",
        "title": "Test Item for Setup Validation",
        "currentPrice": 25.00,
        "maxBid": 30.00,
        "status": "Monitoring",
        "profitPotential": 15.00,
        "ebayUrl": "https://ebay.com/test",
        "brand": "Test Brand",
        "condition": "Very Good",
        "sellerFeedback": 98.5
    }
}'

if ! test_response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "$airtable_auth_header" \
    -H "Content-Type: application/json" \
    -d "$test_item_data" \
    "https://api.airtable.com/v0/$AIRTABLE_BASE_ID/Target%20Items" 2>/dev/null); then
    log_error "curl command failed for test record creation"
    exit 1
fi

http_code=$(response_http_code "$test_response")
ensure_http_code "$http_code" "Airtable test record creation"
log_message "INFO" "Test record creation responded with HTTP code: $http_code"

if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
    echo "✅ Test record created successfully"
    log_message "INFO" "Test record created successfully"

    if ! record_id=$(response_body "$test_response" | jq -r '.id' 2>/dev/null); then
        log_error "Failed to parse record ID from response"
        exit 1
    fi

    if [ -z "$record_id" ] || [ "$record_id" = "null" ]; then
        log_error "Test record creation response did not include a valid record ID"
        exit 1
    fi

    echo "📝 Test record ID: $record_id"
    log_message "INFO" "Test record ID: $record_id"

    echo "🧹 Cleaning up test record..."
    log_message "INFO" "Cleaning up test record"

    if ! delete_response=$(curl -s -w "\n%{http_code}" -X DELETE \
        -H "$airtable_auth_header" \
        "https://api.airtable.com/v0/$AIRTABLE_BASE_ID/Target%20Items/$record_id" 2>/dev/null); then
        log_error "Failed to delete test record"
        exit 1
    fi

    delete_http_code=$(response_http_code "$delete_response")
    ensure_http_code "$delete_http_code" "Airtable test record cleanup"
    if [ "$delete_http_code" -ne 200 ]; then
        log_error "Failed to delete test record with HTTP $delete_http_code"
        exit 1
    fi

    echo "✅ Test record cleaned up"
    log_message "INFO" "Test record cleaned up successfully"
else
    log_error "Failed to create test record with HTTP $http_code"
    echo "❌ Failed to create test record with HTTP $http_code"
    exit 1
fi

echo "🔗 Generating webhook URLs..."
log_message "INFO" "Generating webhook URLs for Make.com"

webhook_base="${MAKE_WEBHOOK_BASE_URL:-https://hook.make.com}"
echo "Webhook URLs for Make.com configuration:"
echo "  Auction Won: $webhook_base/auction-won"
echo "  Item Sold: $webhook_base/item-sold"
echo "  Shipping Update: $webhook_base/shipping-update"
log_message "INFO" "Webhook URLs generated with base: $webhook_base"

echo "📁 Creating directories..."
log_message "INFO" "Creating required directories"

if ! mkdir -p "$LOG_DIR" "$REPO_ROOT/backups" "$REPO_ROOT/temp"; then
    log_error "Failed to create required directories"
    exit 1
fi

echo "✅ Directories created"
log_message "INFO" "Required directories created successfully"

echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo "✅ Configuration validated"
echo "✅ API connections tested"
echo "✅ Airtable database accessible"
echo "✅ Test record created and cleaned up"
echo "✅ Directory structure ready"
echo ""
echo "Next Steps:"
echo "1. Import Make.com scenarios from make-scenarios/ folder"
echo "2. Configure webhook URLs in your services"
echo "3. Set up notification channels (Slack, email)"
echo "4. Run test scenarios with sandbox/small amounts"
echo "5. Monitor performance and adjust settings"
echo ""
echo "Documentation:"
echo "- Setup Guide: docs/setup-guide.md"
echo "- Scenarios Guide: docs/scenarios-guide.md"
echo "- Troubleshooting: docs/troubleshooting.md"
echo ""
echo "⚠️  Important Security Notes:"
echo "- Keep your API keys secure and never commit them to version control"
echo "- Start with small spending limits and increase gradually"
echo "- Monitor all automated activities closely"
echo "- Set up proper error handling and notifications"

log_message "INFO" "Creating setup status file"

if ! cat > "$STATUS_FILE" << EOF
{
    "setup_completed": true,
    "setup_date": "$(date -Iseconds)",
    "apis_tested": {
        "airtable": true,
        "ebay": true,
        "openai": true
    },
    "version": "1.0.0"
}
EOF
then
    log_error "Failed to create setup status file"
    exit 1
fi

echo "✅ Setup status saved to .setup_status"
log_message "INFO" "Setup completed successfully - status file created"
