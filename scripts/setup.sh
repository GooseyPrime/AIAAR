#!/bin/bash

# AIAAR Setup Script
# Automated setup for Airtable database and basic configuration

set -e

echo "🚀 AIAAR Setup Script"
echo "===================="

# Check if required tools are installed
command -v curl >/dev/null 2>&1 || { echo "❌ curl is required but not installed. Aborting." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ jq is required but not installed. Aborting." >&2; exit 1; }

# Check for configuration file
if [ ! -f "config/environment.yml" ]; then
    echo "📝 Creating environment configuration..."
    cp config/environment.template.yml config/environment.yml
    echo "✅ Environment template created at config/environment.yml"
    echo "⚠️  Please edit config/environment.yml with your API keys before continuing"
    exit 1
fi

# Source the configuration (convert YAML to env vars)
echo "📖 Reading configuration..."
export $(grep -v '^#' config/environment.yml | grep -v '^$' | sed 's/: */=/' | sed 's/ *$//')

# Verify required environment variables
required_vars=("AIRTABLE_API_KEY" "AIRTABLE_BASE_ID" "EBAY_CLIENT_ID" "OPENAI_API_KEY")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Required environment variable $var is not set"
        echo "Please update config/environment.yml with your API keys"
        exit 1
    fi
done

echo "✅ Configuration validated"

# Test Airtable connection
echo "🔗 Testing Airtable connection..."
airtable_response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $AIRTABLE_API_KEY" \
    "https://api.airtable.com/v0/$AIRTABLE_BASE_ID/Target%20Items?maxRecords=1")

http_code=$(echo "$airtable_response" | tail -n1)
if [ "$http_code" -eq 200 ]; then
    echo "✅ Airtable connection successful"
elif [ "$http_code" -eq 401 ]; then
    echo "❌ Airtable authentication failed. Check your API key."
    exit 1
elif [ "$http_code" -eq 404 ]; then
    echo "❌ Airtable base not found. Check your Base ID or create tables first."
    exit 1
else
    echo "❌ Airtable connection failed with HTTP $http_code"
    exit 1
fi

# Test eBay API connection
echo "🔗 Testing eBay API connection..."
ebay_response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $EBAY_AUTH_TOKEN" \
    -H "X-EBAY-C-MARKETPLACE-ID: EBAY_US" \
    "https://api.ebay.com/buy/browse/v1/item_summary/search?q=test&limit=1")

http_code=$(echo "$ebay_response" | tail -n1)
if [ "$http_code" -eq 200 ]; then
    echo "✅ eBay API connection successful"
elif [ "$http_code" -eq 401 ]; then
    echo "❌ eBay authentication failed. Check your auth token."
    exit 1
else
    echo "❌ eBay API connection failed with HTTP $http_code"
    exit 1
fi

# Test OpenAI API connection
echo "🔗 Testing OpenAI API connection..."
openai_response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4","messages":[{"role":"user","content":"Hello"}],"max_tokens":5}' \
    "https://api.openai.com/v1/chat/completions")

http_code=$(echo "$openai_response" | tail -n1)
if [ "$http_code" -eq 200 ]; then
    echo "✅ OpenAI API connection successful"
elif [ "$http_code" -eq 401 ]; then
    echo "❌ OpenAI authentication failed. Check your API key."
    exit 1
else
    echo "❌ OpenAI API connection failed with HTTP $http_code"
    exit 1
fi

# Create initial test records
echo "📊 Creating test data in Airtable..."

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

test_response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $AIRTABLE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$test_item_data" \
    "https://api.airtable.com/v0/$AIRTABLE_BASE_ID/Target%20Items")

http_code=$(echo "$test_response" | tail -n1)
if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
    echo "✅ Test record created successfully"
    # Extract record ID for cleanup
    record_id=$(echo "$test_response" | head -n -1 | jq -r '.id')
    echo "📝 Test record ID: $record_id"
    
    # Clean up test record
    echo "🧹 Cleaning up test record..."
    curl -s -X DELETE \
        -H "Authorization: Bearer $AIRTABLE_API_KEY" \
        "https://api.airtable.com/v0/$AIRTABLE_BASE_ID/Target%20Items/$record_id" > /dev/null
    echo "✅ Test record cleaned up"
else
    echo "❌ Failed to create test record with HTTP $http_code"
    exit 1
fi

# Generate webhook URLs for Make.com
echo "🔗 Generating webhook URLs..."
webhook_base="${MAKE_WEBHOOK_BASE_URL:-https://hook.make.com}"
echo "Webhook URLs for Make.com configuration:"
echo "  Auction Won: $webhook_base/auction-won"
echo "  Item Sold: $webhook_base/item-sold"
echo "  Shipping Update: $webhook_base/shipping-update"

# Create directories for logs and backups
echo "📁 Creating directories..."
mkdir -p logs backups temp
echo "✅ Directories created"

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
cat > .setup_status << EOF
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

echo "✅ Setup status saved to .setup_status"