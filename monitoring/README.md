# Production Monitoring & Alerting

This repository is primarily a scaffold, but production operation still needs a lightweight monitoring routine. Use this guide to create the minimum dashboards, log reviews, and alerts needed to keep Make.com scenarios and Airtable-backed workflows healthy 24/7.

## Monitoring goals

- Detect scenario failures before they create stale bids, missing inventory, or missed resale updates
- Confirm Airtable remains reachable for reads/writes
- Confirm Make.com webhook/API endpoints remain reachable
- Alert on failure trends, slowdowns, and unusual spending patterns

## Required dashboards

### 1. Scenario operations dashboard

Track each production Make.com scenario with:

- scenario name / owner
- last successful run timestamp
- last failed run timestamp
- success rate over 1 hour and 24 hours
- median and p95 execution duration
- operations consumed per run
- queue or backlog indicators if scenarios are event-driven

Recommended panels:

1. **Scenario heartbeat** - one tile per scenario showing green/yellow/red status
2. **Failures over time** - count of failed runs grouped by scenario
3. **Execution latency** - median/p95 runtime to catch slow modules before timeouts
4. **Operations usage** - daily Make.com operations burn rate versus plan limits

### 2. Airtable data health dashboard

Track:

- API success/failure rate
- 401/403 authentication errors
- 404/422 schema or mapping errors
- record creation/update counts
- stale records stuck in `Monitoring`, `Won`, or similar operational states

Recommended panels:

1. **Airtable API status** - success rate and latest HTTP status
2. **Write failures** - failed record creates/updates over time
3. **Stale workflow records** - items not updated within expected SLA windows
4. **Manual audit queue** - records needing operator review

### 3. Commercial risk dashboard

Track business-impact signals alongside technical health:

- daily spend versus configured limit
- count of bids placed
- won items awaiting payment/shipping
- active listings missing tracking or resale updates
- estimated ROI anomalies

## Scenario log monitoring

Review Make.com execution logs for every production scenario. At minimum, capture:

- failed module name
- error message text
- timestamp
- scenario ID / run ID
- source payload or record identifier
- retry count or whether the run auto-recovered

### Daily log review checklist

1. Check for any scenario with no successful run in the last 15 minutes (or the expected schedule interval)
2. Review all failed runs from the last 24 hours
3. Confirm retries cleared transient API/network failures
4. Open an incident for repeated mapping/schema failures
5. Verify no webhook-triggered scenario has gone quiet unexpectedly

### Failure patterns that should page an operator

- 3 consecutive failures for the same scenario
- no successful run in 2 expected execution windows
- Airtable authentication or permission failures
- webhook trigger volume suddenly dropping to zero during business hours
- spending or bid activity exceeding normal limits

## Alert setup

Configure alerts in whichever system receives operational notifications (email, Slack, PagerDuty, etc.).

### Critical alerts

Trigger immediately for:

- Make.com scenario disabled or auto-deactivated
- 3 consecutive scenario failures
- Airtable API check returning non-200
- Make.com endpoint check returning 5xx or no response
- daily spending limit reached or exceeded

### Warning alerts

Trigger for:

- success rate under 95% over 1 hour
- p95 scenario runtime above 2x normal baseline
- Make.com operations usage above 80% of plan
- stale inventory/payment/shipping records older than SLA
- repeated HTTP 429 rate-limit responses

### Alert routing

- **Primary**: on-call operator / owner
- **Secondary**: backup operator
- **Triage channel**: shared Slack/email thread with scenario name, timestamp, HTTP status, and record ID

## Shell health-check scaffold

Use the repository script below for a lightweight external probe:

```bash
./scripts/monitoring-health-check.sh --dry-run
```

Then run it live in production with environment values loaded:

```bash
./scripts/monitoring-health-check.sh
```

For schedulers or separate production config files, point the script at an explicit env file:

```bash
./scripts/monitoring-health-check.sh --env-file /path/to/production.env
```

What it checks:

- Make.com endpoint reachability using `MAKE_HEALTHCHECK_URL`, or host-level reachability using `MAKE_WEBHOOK_BASE_URL` when no full endpoint probe is configured
- Airtable table-read success against a designated existing table using `AIRTABLE_API_KEY`, `AIRTABLE_BASE_ID`, `AIRTABLE_HEALTHCHECK_TABLE` (defaults to `Target Items`), and an optional `AIRTABLE_API_BASE_URL` override, which also surfaces auth/permission problems separately from missing-table problems

What it does **not** check:

- scenario business logic correctness
- webhook payload mappings
- end-to-end order/bid lifecycle completion

`AIRTABLE_HEALTHCHECK_TABLE` should point to a table that exists in every production environment. If your base does not include `Target Items`, override the value in `.env` before scheduling live checks.
`AIRTABLE_API_BASE_URL` is optional and defaults to `https://api.airtable.com/v0`.
`MAKE_WEBHOOK_BASE_URL` is only a host-level fallback probe. It treats any completed 2xx-4xx HTTP response as proof that the host is reachable, not that a specific scenario path is healthy. Set `MAKE_HEALTHCHECK_URL` if you want the script to validate a specific production Make.com endpoint path.

## Suggested scheduling

- run the shell health check every 5 minutes from an external scheduler
- send output to centralized logs
- notify on first failure and auto-resolve after the next successful run
- retain logs for at least 30 days for trend review

## Incident response starter

When an alert fires:

1. Identify the failing scenario or external dependency
2. Check Make.com execution history and the latest Airtable/API errors
3. Pause unsafe automations if bids, purchases, or listings could be impacted
4. Fix credentials, mappings, or rate-limit pressure
5. Rerun `./scripts/monitoring-health-check.sh`
6. Confirm the next scheduled scenario run succeeds

## Related repository references

- `scripts/monitoring-health-check.sh`
- `scripts/health-check.sh`
- `docs/troubleshooting.md`
- `docs/setup-guide.md`
