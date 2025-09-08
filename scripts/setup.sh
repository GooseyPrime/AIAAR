#!/bin/bash

# AIAAR Setup Script
# Automated setup for Airtable database and basic configuration

# Enable robust error handling
set -euo pipefail

# Error logging and handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/../logs/setup.log"
ERROR_LOG="${SCRIPT_DIR}/../logs/setup_errors.log"

# Create logs directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages with timestamp
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to log errors
log_error() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [ERROR] $message" | tee -a "$ERROR_LOG" >&2
}

# Error handler function
error_handler() {
    local line_number="$1"
    local error_code="$2"
    local command="$3"
    log_error "Script failed at line $line_number with exit code $error_code"
    log_error "Failed command: $command"
    log_error "Current working directory: $(pwd)"
    log_error "Environment variables: $(env | grep -E '^(AIRTABLE|EBAY|OPENAI)' || echo 'No relevant env vars found')"
    echo "❌ Setup failed. Check error logs at $ERROR_LOG for details." >&2
    exit "$error_code"
}

# Set up error trap
trap 'error_handler ${LINENO} $? "$BASH_COMMAND"' ERR

# Initialize logging
log_message "INFO" "Starting AIAAR setup script"

echo "🚀 AIAAR Setup Script"
echo "===================="
log_message "INFO" "AIAAR Setup Script started"

# Check if required tools are installed
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

# Check for configuration file
log_message "INFO" "Checking for configuration file"
if [ ! -f "config/environment.yml" ]; then
    log_message "WARN" "Environment configuration not found, creating template"
    echo "📝 Creating environment configuration..."
    if ! cp config/environment.template.yml config/environment.yml; then
        log_error "Failed to copy environment template"
        exit 1
    fi
    echo "✅ Environment template created at config/environment.yml"
    echo "⚠️  Please edit config/environment.yml with your API keys before continuing"
    log_message "INFO" "Environment template created, user action required"
    exit 1
fi

# Source the configuration (convert YAML to env vars)
log_message "INFO" "Reading configuration from environment.yml"
echo "📖 Reading configuration..."
if ! export $(grep -v '^#' config/environment.yml | grep -v '^$' | sed 's/: */=/' | sed 's/ *$//'); then
    log_error "Failed to parse environment configuration"
    exit 1
fi

# Verify required environment variables
log_message "INFO" "Verifying required environment variables"
required_vars=("AIRTABLE_API_KEY" "AIRTABLE_BASE_ID" "EBAY_CLIENT_ID" "OPENAI_API_KEY")
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        log_error "Required environment variable $var is not set"
        echo "❌ Required environment variable $var is not set"
        echo "Please update config/environment.yml with your API keys"
        exit 1
    fi
    log_message "INFO" "Environment variable $var is set"
done

echo "✅ Configuration validated"
log_message "INFO" "All required environment variables validated"

# Test Airtable connection
echo "🔗 Testing Airtable connection..."
log_message "INFO" "Testing Airtable API connection"

if ! airtable_response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $AIRTABLE_API_KEY" \
    "https://api.airtable.com/v0/$AIRTABLE_BASE_ID/Target%20Items?maxRecords=1" 2>/dev/null); then
    log_error "curl command failed for Airtable API test"
    exit 1
fi

http_code=$(echo "$airtable_response" | tail -n1)
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

# Test eBay API connection
echo "🔗 Testing eBay API connection..."
log_message "INFO" "Testing eBay API connection"

if ! ebay_response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${EBAY_AUTH_TOKEN:-}" \
    -H "X-EBAY-C-MARKETPLACE-ID: EBAY_US" \
    "https://api.ebay.com/buy/browse/v1/item_summary/search?q=test&limit=1" 2>/dev/null); then
    log_error "curl command failed for eBay API test"
    exit 1
fi

http_code=$(echo "$ebay_response" | tail -n1)
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

# Test OpenAI API connection
echo "🔗 Testing OpenAI API connection..."
log_message "INFO" "Testing OpenAI API connection"

if ! openai_response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4","messages":[{"role":"user","content":"Hello"}],"max_tokens":5}' \
    "https://api.openai.com/v1/chat/completions" 2>/dev/null); then
    log_error "curl command failed for OpenAI API test"
    exit 1
fi

http_code=$(echo "$openai_response" | tail -n1)
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

# Create initial test records
echo "📊 Creating test data in Airtable..."
log_message "INFO" "Creating test data in Airtable"

# Create a test target item
test_item_data='{
    "fields": {
        "itemId": "TEST-ITEM-001",
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
    -H "Authorization: Bearer $AIRTABLE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$test_item_data" \
    "https://api.airtable.com/v0/$AIRTABLE_BASE_ID/Target%20Items" 2>/dev/null); then
    log_error "curl command failed for test record creation"
    exit 1
fi

http_code=$(echo "$test_response" | tail -n1)
log_message "INFO" "Test record creation responded with HTTP code: $http_code"

if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
    echo "✅ Test record created successfully"
    log_message "INFO" "Test record created successfully"
    
    # Extract record ID for cleanup
    if ! record_id=$(echo "$test_response" | head -n -1 | jq -r '.id' 2>/dev/null); then
        log_error "Failed to parse record ID from response"
        exit 1
    fi
    
    echo "📝 Test record ID: $record_id"
    log_message "INFO" "Test record ID: $record_id"
    
    # Clean up test record
    echo "🧹 Cleaning up test record..."
    log_message "INFO" "Cleaning up test record"
    
    if ! curl -s -X DELETE \
        -H "Authorization: Bearer $AIRTABLE_API_KEY" \
        "https://api.airtable.com/v0/$AIRTABLE_BASE_ID/Target%20Items/$record_id" > /dev/null 2>&1; then
        log_error "Failed to delete test record"
        exit 1
    fi
    
    echo "✅ Test record cleaned up"
    log_message "INFO" "Test record cleaned up successfully"
else
    log_error "Failed to create test record with HTTP $http_code"
    echo "❌ Failed to create test record with HTTP $http_code"
    exit 1
fi

# Generate webhook URLs for Make.com
echo "🔗 Generating webhook URLs..."
log_message "INFO" "Generating webhook URLs for Make.com"

webhook_base="${MAKE_WEBHOOK_BASE_URL:-https://hook.make.com}"
echo "Webhook URLs for Make.com configuration:"
echo "  Auction Won: $webhook_base/auction-won"
echo "  Item Sold: $webhook_base/item-sold"
echo "  Shipping Update: $webhook_base/shipping-update"
log_message "INFO" "Webhook URLs generated with base: $webhook_base"

# Create directories for logs and backups
echo "📁 Creating directories..."
log_message "INFO" "Creating required directories"

if ! mkdir -p logs backups temp; then
    log_error "Failed to create required directories"
    exit 1
fi

echo "✅ Directories created"
log_message "INFO" "Required directories created successfully"

# Generate summary report
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

# Create a status file
log_message "INFO" "Creating setup status file"

if ! cat > .setup_status << EOF
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