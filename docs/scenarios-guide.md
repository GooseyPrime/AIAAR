# Make.com Scenarios Guide

## Overview

The AIAAR system consists of 8 interconnected Make.com scenarios that automate the entire auction-to-resale process. Each scenario handles a specific aspect of the operation.

## Scenario Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Scenario 1    │───▶│   Scenario 2    │───▶│   Scenario 3    │
│ Auction Discovery│    │ Item Analysis   │    │ Bidding Monitor │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Scenario 4    │    │   Scenario 5    │    │   Scenario 6    │
│ Win Processing  │    │ Shipping Track  │    │ Listing Resale  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Scenario 7    │    │   Scenario 8    │    │    Analytics    │
│ Sales Management│    │   Reporting     │    │   Dashboard     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Scenario 1: Auction Discovery & Research

**Purpose**: Continuously monitor eBay for viable auction opportunities

**Trigger**: Schedule (every 30 minutes, 6 AM - 11 PM)

**Key Modules**:
1. **Schedule Trigger** - Runs every 30 minutes during business hours
2. **eBay Search** - Searches for electronics, collectibles, branded items
3. **Parse Results** - Processes eBay API response
4. **Filter Items** - Applies quality criteria (seller feedback >95%, price <$500)

**Outputs**:
- Filtered list of viable auction items
- Basic item data for analysis

**Configuration**:
```json
{
  "searchCriteria": "(electronics,collectibles,branded) -parts -repair",
  "priceRange": "[10..500]",
  "conditions": ["New", "Like New", "Very Good"],
  "minSellerFeedback": 95
}
```

## Scenario 2: Item Analysis & Valuation

**Purpose**: AI-powered analysis and market research for discovered items

**Trigger**: Output from Scenario 1

**Key Modules**:
1. **AI Analysis** - OpenAI analyzes item potential and extracts key data
2. **Market Research** - Searches sold listings on eBay
3. **Amazon Research** - Checks current Amazon pricing
4. **Profitability Calculator** - Calculates potential profit and max bid
5. **ROI Filter** - Filters items with minimum 25% ROI

**Outputs**:
- AI analysis with brand, model, features, and risk assessment
- Market pricing data
- Calculated max bid and profit potential

**AI Analysis Output**:
```json
{
  "brand": "Apple",
  "model": "iPhone 13 Pro",
  "features": ["128GB", "Unlocked", "Excellent condition"],
  "retail_value": 899,
  "resale_difficulty": 3,
  "shipping_complexity": 2,
  "red_flags": []
}
```

## Scenario 3: Bidding & Monitoring

**Purpose**: Strategic automated bidding with timing optimization

**Trigger**: Schedule (every 5 minutes) + Scenario 2 output

**Key Modules**:
1. **Airtable Storage** - Saves viable items to watch list
2. **Active Item Check** - Retrieves items being monitored
3. **Auction Status** - Checks current bid and time remaining
4. **Bidding Router** - Routes to appropriate bidding strategy:
   - **>2 hours**: Monitor only
   - **30min-2hr**: Conservative bid (60% of max)
   - **<30min**: Aggressive bid (90% of max)
5. **Bid Placement** - Places actual bids on eBay

**Bidding Strategy**:
- Conservative: 60% of calculated max bid
- Aggressive: 90% of calculated max bid
- Safety margin: Never exceed calculated max bid

## Scenario 4: Win Processing & Inventory

**Purpose**: Automated processing when auctions are won

**Trigger**: Webhook from eBay (auction won)

**Key Modules**:
1. **Win Status Update** - Marks item as "Won" in Airtable
2. **Payment Processing** - Automatically pays seller via PayPal
3. **Inventory Creation** - Generates unique inventory ID
4. **Notification System** - Sends Slack/email alerts

**Inventory ID Format**: `INV-YYYYMMDD-XXXXXX`

## Scenario 5: Shipping & Receiving

**Purpose**: Tracking shipments and delivery confirmation

**Trigger**: Email monitoring + Daily schedule

**Key Modules**:
1. **Email Monitor** - Watches for shipping notifications
2. **AI Extraction** - Extracts tracking info from emails
3. **Tracking Updates** - Updates Airtable with tracking data
4. **Delivery Check** - Daily checks of shipment status
5. **Delivery Confirmation** - Marks items as delivered

**Supported Carriers**:
- USPS
- FedEx  
- UPS
- DHL

## Scenario 6: Listing & Resale

**Purpose**: Automated creation of optimized eBay listings

**Trigger**: Items marked as "Delivered"

**Key Modules**:
1. **Item Processing** - Gets delivered items ready for listing
2. **AI Content Generation** - Creates optimized titles and descriptions
3. **eBay Listing** - Creates actual eBay auction/BIN listing
4. **Inventory Update** - Updates records with listing information

**Pricing Strategy**:
- Starting Price: Purchase price × 1.4
- Buy It Now: Purchase price × 1.8
- Duration: 7 days
- Returns: 30-day money back

## Scenario 7: Sales Management

**Purpose**: Processing sales and shipping management

**Trigger**: Webhook from eBay (item sold)

**Key Modules**:
1. **Sale Processing** - Marks item as sold
2. **Profit Calculation** - Calculates final profit including fees
3. **Shipping Label** - Generates label via ShipStation
4. **Buyer Communication** - Sends tracking info to buyer
5. **Success Notification** - Alerts via Slack/email

**Fee Calculations**:
- eBay fees: 13% of sale price
- PayPal fees: 3% of sale price
- Shipping: $12 (USPS Priority Mail)

## Scenario 8: Analytics & Reporting

**Purpose**: Performance tracking and business intelligence

**Trigger**: Daily (11 PM) and Weekly (Sunday 8 PM)

**Key Modules**:
1. **Daily Stats** - Calculates daily performance metrics
2. **AI Report Generation** - Creates comprehensive reports
3. **Email Reports** - Sends detailed performance summaries
4. **Weekly Analysis** - Provides strategic insights and recommendations

**Key Metrics**:
- Items won/sold
- Revenue and profit
- ROI percentage
- Win rate
- Active listings
- Category performance

## Data Flow Between Scenarios

1. **Discovery → Analysis**: Item data passes from search to AI analysis
2. **Analysis → Bidding**: Viable items added to monitoring list
3. **Bidding → Processing**: Won items trigger payment and inventory
4. **Processing → Shipping**: Inventory items tracked through delivery
5. **Shipping → Listing**: Delivered items prepared for resale
6. **Listing → Sales**: Listed items processed when sold
7. **All → Analytics**: Performance data aggregated for reporting

## Error Handling

Each scenario includes:
- **Retry Logic**: 3-5 attempts for failed operations
- **Timeout Settings**: 30-60 second timeouts
- **Error Notifications**: Slack/email alerts for failures
- **Graceful Degradation**: Fallback responses for AI services
- **Data Validation**: Input/output validation at each step

## Monitoring & Optimization

### Performance Metrics
- Execution time per scenario
- Success/failure rates
- API rate limit usage
- Data accuracy and consistency

### Optimization Strategies
- Adjust search criteria based on success rates
- Fine-tune AI prompts for better analysis
- Optimize bidding timing and amounts
- Improve pricing strategies using historical data

## Security Considerations

- **API Key Management**: Stored as encrypted variables
- **Rate Limiting**: Respects all API rate limits
- **Data Privacy**: No sensitive data in logs
- **Access Control**: Minimal required permissions
- **Audit Logging**: All operations logged for review

## Troubleshooting

Common issues and solutions:

1. **eBay API Errors**: Check token validity and rate limits
2. **AI Analysis Failures**: Use fallback responses
3. **Bidding Issues**: Verify auction status and bid amounts
4. **Data Sync Problems**: Check Airtable connectivity
5. **Email Processing**: Verify email filters and parsing

See `/docs/troubleshooting.md` for detailed solutions.