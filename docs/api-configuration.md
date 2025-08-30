# API Configuration Guide

## Overview

This guide provides detailed information about configuring and using the API integration modules for the AIAAR system.

## API Modules

### eBay API (`api-modules/ebay-api.json`)

**Authentication**: OAuth 2.0 Bearer Token

**Key Endpoints**:
- `searchItems`: Search for auction items
- `getItemDetails`: Get detailed information about specific items
- `placeBid`: Place bids on auction items
- `addItem`: Create new listings
- `sendMessage`: Send messages to buyers/sellers

**Rate Limits**:
- Search: 5,000 requests/day
- Bidding: 100 requests/hour
- Listing: 500 requests/day

**Configuration Example**:
```json
{
  "ebay_client_id": "YourClientId",
  "ebay_client_secret": "YourClientSecret", 
  "ebay_auth_token": "YourAuthToken",
  "marketplace_id": "EBAY_US",
  "sandbox_mode": true
}
```

### OpenAI API (`api-modules/openai-api.json`)

**Authentication**: Bearer Token

**Key Endpoints**:
- `analyzeItem`: AI-powered item analysis
- `generateListingContent`: Create optimized listings
- `extractTrackingInfo`: Extract shipping data from emails
- `generateDailyReport`: Performance report generation
- `generateWeeklyInsights`: Strategic analysis

**Rate Limits**:
- 60 requests/minute
- 150,000 tokens/minute

**Configuration Example**:
```json
{
  "openai_api_key": "sk-your-api-key",
  "model": "gpt-4",
  "temperature": 0.3,
  "max_tokens": 500
}
```

### Airtable API (`api-modules/airtable-api.json`)

**Authentication**: Bearer Token

**Key Operations**:
- `createRecord`: Add new records
- `updateRecord`: Modify existing records
- `searchRecords`: Query with filters
- `listRecords`: Paginated data retrieval
- `deleteRecord`: Remove records

**Rate Limits**:
- 5 requests/second
- 1,000 requests/hour

**Configuration Example**:
```json
{
  "airtable_api_key": "keySampleApiKey",
  "base_id": "appSampleBaseId"
}
```

## Authentication Setup

### eBay OAuth 2.0

1. **Register Application**:
   - Visit [eBay Developers](https://developer.ebay.com/)
   - Create new application
   - Configure redirect URLs

2. **Generate Tokens**:
   ```bash
   # Get authorization code
   curl "https://auth.ebay.com/oauth2/authorize?client_id=YOUR_CLIENT_ID&response_type=code&redirect_uri=YOUR_REDIRECT_URI&scope=https://api.ebay.com/oauth/api_scope"
   
   # Exchange for access token
   curl -X POST "https://api.ebay.com/identity/v1/oauth2/token" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -H "Authorization: Basic $(echo -n 'CLIENT_ID:CLIENT_SECRET' | base64)" \
     -d "grant_type=authorization_code&code=AUTH_CODE&redirect_uri=YOUR_REDIRECT_URI"
   ```

3. **Token Refresh**:
   ```bash
   curl -X POST "https://api.ebay.com/identity/v1/oauth2/token" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -H "Authorization: Basic $(echo -n 'CLIENT_ID:CLIENT_SECRET' | base64)" \
     -d "grant_type=refresh_token&refresh_token=REFRESH_TOKEN"
   ```

### OpenAI API Key

1. **Generate Key**:
   - Visit [OpenAI Platform](https://platform.openai.com/api-keys)
   - Create new secret key
   - Set usage limits

2. **Test Connection**:
   ```bash
   curl "https://api.openai.com/v1/chat/completions" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer YOUR_API_KEY" \
     -d '{
       "model": "gpt-4",
       "messages": [{"role": "user", "content": "Hello"}],
       "max_tokens": 5
     }'
   ```

### Airtable API

1. **Generate Token**:
   - Visit [Airtable Account](https://airtable.com/account)
   - Create personal access token
   - Set appropriate scopes

2. **Test Connection**:
   ```bash
   curl "https://api.airtable.com/v0/YOUR_BASE_ID/YOUR_TABLE_NAME" \
     -H "Authorization: Bearer YOUR_API_KEY"
   ```

## Error Handling

### Common Error Patterns

1. **Authentication Errors (401)**:
   ```json
   {
     "error": "Invalid token",
     "retry": false,
     "action": "regenerate_token"
   }
   ```

2. **Rate Limit Errors (429)**:
   ```json
   {
     "error": "Rate limit exceeded", 
     "retry": true,
     "retry_after": 60,
     "action": "exponential_backoff"
   }
   ```

3. **Validation Errors (422)**:
   ```json
   {
     "error": "Invalid data format",
     "retry": false,
     "action": "fix_data_format"
   }
   ```

### Retry Logic

```javascript
async function apiCallWithRetry(apiCall, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await apiCall();
    } catch (error) {
      if (error.status === 429) {
        // Rate limit - exponential backoff
        const delay = Math.pow(2, attempt) * 1000;
        await new Promise(resolve => setTimeout(resolve, delay));
      } else if (error.status >= 500) {
        // Server error - retry
        const delay = attempt * 1000;
        await new Promise(resolve => setTimeout(resolve, delay));
      } else {
        // Client error - don't retry
        throw error;
      }
    }
  }
  throw new Error(`Max retries (${maxRetries}) exceeded`);
}
```

## Rate Limit Management

### eBay API Limits

- **Daily Limits**: Vary by endpoint and account type
- **Per-second Limits**: 10 requests/second
- **Monitoring**: Check `X-RateLimit-*` headers

### OpenAI Rate Limits

- **Tier-based**: Depends on account usage history
- **Token Limits**: Track input + output tokens
- **Monitoring**: Check response headers

### Airtable Rate Limits

- **Base Limits**: 1,000 requests/hour per base
- **Global Limits**: 5 requests/second per account
- **Monitoring**: Check `X-RateLimit-*` headers

## Data Formatting

### eBay Search Results

```json
{
  "itemSummaries": [
    {
      "itemId": "123456789",
      "title": "Sample Item",
      "currentPrice": {
        "value": "99.99",
        "currency": "USD"
      },
      "condition": "Very Good",
      "sellerFeedbackPercentage": 98.5,
      "itemEndDate": "2024-01-15T18:30:00.000Z"
    }
  ]
}
```

### OpenAI Analysis Response

```json
{
  "choices": [
    {
      "message": {
        "content": "{\"brand\":\"Apple\",\"model\":\"iPhone 13\",\"retail_value\":799,\"resale_difficulty\":3}"
      }
    }
  ],
  "usage": {
    "prompt_tokens": 150,
    "completion_tokens": 75,
    "total_tokens": 225
  }
}
```

### Airtable Record Format

```json
{
  "fields": {
    "itemId": "123456789",
    "title": "Sample Item",
    "currentPrice": 99.99,
    "status": "Monitoring",
    "createdDate": "2024-01-01T00:00:00.000Z"
  }
}
```

## Security Best Practices

### API Key Management

1. **Environment Variables**: Store keys in environment variables
2. **Rotation**: Regularly rotate API keys
3. **Permissions**: Use minimal required permissions
4. **Monitoring**: Monitor for unauthorized usage

### Request Security

1. **HTTPS Only**: Always use HTTPS for API calls
2. **Validation**: Validate all input data
3. **Sanitization**: Sanitize data before processing
4. **Logging**: Log API calls for audit trail

### Error Information

1. **Sensitive Data**: Don't log sensitive information
2. **Error Details**: Provide minimal error details to clients
3. **Rate Limiting**: Implement client-side rate limiting
4. **Timeout**: Set appropriate request timeouts

## Testing

### Unit Tests

```javascript
// Test eBay API search
async function testEbaySearch() {
  const result = await ebayApi.searchItems({
    q: "test item",
    limit: 1
  });
  assert(result.itemSummaries.length <= 1);
}

// Test OpenAI analysis
async function testOpenAIAnalysis() {
  const result = await openaiApi.analyzeItem({
    title: "Apple iPhone 13",
    price: 500,
    condition: "Very Good"
  });
  const analysis = JSON.parse(result.choices[0].message.content);
  assert(analysis.brand === "Apple");
}
```

### Integration Tests

```javascript
// Test full workflow
async function testWorkflow() {
  // 1. Search for items
  const searchResults = await ebayApi.searchItems({...});
  
  // 2. Analyze first item
  const analysis = await openaiApi.analyzeItem(searchResults.itemSummaries[0]);
  
  // 3. Store in Airtable
  const record = await airtableApi.createRecord({
    table: "Target Items",
    fields: {...}
  });
  
  assert(record.id);
}
```

## Monitoring

### Key Metrics

1. **Success Rate**: Percentage of successful API calls
2. **Response Time**: Average API response times
3. **Error Rate**: Percentage of failed requests
4. **Rate Limit Usage**: Percentage of rate limits used

### Alerting

Set up alerts for:
- API error rates > 5%
- Response times > 5 seconds
- Rate limit usage > 80%
- Authentication failures

### Logging

```javascript
// Structured logging
const apiLogger = {
  logRequest: (endpoint, params) => {
    console.log(JSON.stringify({
      timestamp: new Date().toISOString(),
      type: "api_request",
      endpoint,
      params: sanitizeParams(params)
    }));
  },
  
  logResponse: (endpoint, status, duration) => {
    console.log(JSON.stringify({
      timestamp: new Date().toISOString(),
      type: "api_response", 
      endpoint,
      status,
      duration_ms: duration
    }));
  }
};
```