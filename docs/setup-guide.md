# AIAAR Setup Guide

## Prerequisites

Before setting up the Automated Auction Assistant, ensure you have:

1. **Make.com Account** (Team plan recommended for advanced features)
2. **eBay Developer Account** with API access
3. **OpenAI API Account** with GPT-4 access
4. **Airtable Account** (Pro plan for advanced features)
5. **PayPal Developer Account** for automated payments
6. **ShipStation Account** for shipping management
7. **Email Account** (Gmail/Outlook) for notifications

## Step 1: API Key Configuration

### 1.1 eBay API Setup

1. Visit [eBay Developers Program](https://developer.ebay.com/)
2. Create a new application
3. Generate sandbox and production keys
4. Configure OAuth redirect URLs
5. Note your:
   - Client ID
   - Client Secret
   - Auth Token (from User Token flow)

### 1.2 OpenAI API Setup

1. Visit [OpenAI API Platform](https://platform.openai.com/)
2. Create API key with GPT-4 access
3. Set usage limits and billing
4. Note your API key

### 1.3 Airtable Setup

1. Create new base using `/database/airtable-schema.json`
2. Generate API key from account settings
3. Note your Base ID from the base URL

### 1.4 PayPal Developer Setup

1. Visit [PayPal Developer](https://developer.paypal.com/)
2. Create sandbox application
3. Generate Client ID and Secret
4. Configure webhooks for payment notifications

### 1.5 ShipStation Setup

1. Create ShipStation account
2. Generate API key and secret
3. Configure carrier accounts (USPS, FedEx, UPS)

## Step 2: Environment Configuration

1. Copy `/config/environment.template.yml` to `/config/environment.yml`
2. Fill in all API keys and configuration values:

```yaml
# eBay Configuration
ebay:
  client_id: "YOUR_EBAY_CLIENT_ID"
  client_secret: "YOUR_EBAY_CLIENT_SECRET"
  auth_token: "YOUR_EBAY_AUTH_TOKEN"
  marketplace_id: "EBAY_US"
  sandbox_mode: true  # Set to false for production

# OpenAI Configuration
openai:
  api_key: "YOUR_OPENAI_API_KEY"
  model: "gpt-4"

# Continue for all services...
```

## Step 3: Airtable Database Setup

### 3.1 Create Tables

Use the schema in `/database/airtable-schema.json` to create:

1. **Target Items** - Track discovered and monitored auctions
2. **Inventory** - Manage purchased items and sales
3. **Performance** - Daily/weekly analytics data

### 3.2 Configure Views

Create these views in Airtable:

**Target Items Views:**
- `Active Monitoring` - Status = "Monitoring"
- `Won Items` - Status = "Won"
- `Ready to List` - Status = "Delivered", Listed = FALSE

**Performance Views:**
- `Daily Stats` - Group by Date
- `Weekly Summary` - Group by Week
- `Monthly Overview` - Group by Month

## Step 4: Make.com Scenario Import

### 4.1 Import Scenarios

1. Access your Make.com dashboard
2. Create new scenarios for each file in `/make-scenarios/`:
   - scenario-1-auction-discovery.json
   - scenario-2-item-analysis.json
   - scenario-3-bidding-monitoring.json
   - scenario-4-win-processing.json
   - scenario-5-shipping-receiving.json
   - scenario-6-listing-resale.json
   - scenario-7-sales-management.json
   - scenario-8-analytics-reporting.json

### 4.2 Configure Variables

In each scenario, set these variables:
- `ebay_token` - Your eBay API token
- `openai_api_key` - Your OpenAI API key
- `airtable_api_key` - Your Airtable API key
- `airtable_base_id` - Your Airtable base ID

### 4.3 Set Up Webhooks

Configure webhooks for:
- Auction won notifications: `/auction-won`
- Item sold notifications: `/item-sold`
- Shipping updates: `/shipping-update`

## Step 5: Safety Configuration

### 5.1 Set Spending Limits

Configure these safety limits in Make.com variables:
- `daily_spending_limit`: $200
- `max_bid_per_item`: $100
- `min_seller_feedback`: 95%

### 5.2 Restricted Categories

Add these to avoid problematic items:
- Automotive parts
- Health products
- Adult items
- Restricted/regulated items

### 5.3 Error Handling

Enable error handling for each scenario:
- Max consecutive errors: 5
- Auto-deactivate on critical failures
- Email notifications for errors

## Step 6: Testing & Validation

### 6.1 Sandbox Testing

1. Start with eBay sandbox environment
2. Use small test amounts ($1-5)
3. Verify all data flows to Airtable
4. Test email/Slack notifications

### 6.2 Scenario Testing

Test each scenario individually:

1. **Scenario 1**: Verify eBay search returns items
2. **Scenario 2**: Check AI analysis accuracy
3. **Scenario 3**: Test bidding logic (sandbox only)
4. **Scenario 4**: Verify inventory creation
5. **Scenario 5**: Test shipping tracking
6. **Scenario 6**: Validate listing creation
7. **Scenario 7**: Check sales processing
8. **Scenario 8**: Review analytics reports

### 6.3 Integration Testing

1. Run full end-to-end test
2. Monitor data consistency
3. Verify profit calculations
4. Check notification delivery

## Step 7: Production Deployment

### 7.1 Switch to Production

1. Update eBay API to production mode
2. Switch PayPal to live environment
3. Configure real email addresses
4. Set production spending limits

### 7.2 Monitoring Setup

1. Enable all scenarios
2. Set up monitoring dashboards
3. Configure alert thresholds
4. Schedule regular reviews

### 7.3 Backup & Recovery

1. Export Airtable data regularly
2. Backup Make.com scenario configurations
3. Document API keys securely
4. Create disaster recovery plan

## Step 8: Optimization

### 8.1 Performance Tuning

- Adjust search criteria based on success rates
- Optimize bidding strategies using historical data
- Fine-tune AI prompts for better analysis
- Improve pricing strategies

### 8.2 Scaling

- Increase spending limits gradually
- Add more product categories
- Expand to additional marketplaces
- Implement advanced analytics

## Troubleshooting

See `/docs/troubleshooting.md` for common issues and solutions.

## Support

- Check scenario logs in Make.com
- Review Airtable data for inconsistencies
- Monitor API rate limits
- Contact support channels for each service

## Security Best Practices

1. **Never commit API keys to version control**
2. **Use environment variables for sensitive data**
3. **Regularly rotate API keys**
4. **Monitor for unauthorized access**
5. **Enable two-factor authentication on all accounts**
6. **Use minimal required permissions**
7. **Regularly audit access logs**

## Next Steps

Once setup is complete:
1. Monitor performance for 1 week
2. Analyze ROI and success rates
3. Adjust strategies based on data
4. Scale up gradually
5. Explore advanced features