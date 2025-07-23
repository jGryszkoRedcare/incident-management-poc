# PagerDury Test Setup

## Obtain an API Key

There are two different APIs in PagerDuty, and the authentication method depends on which one you're using:

🔔 1. Events API v2 — for triggering alerts/incidents
This is the API used in curl to simulate an alert (like in your test script). It does not require authentication in the traditional sense — it uses a routing key to authenticate.

✅ Authentication method: routing_key

```bash
curl -X POST https://events.pagerduty.com/v2/enqueue \
  -H "Content-Type: application/json" \
  -d '{
    "routing_key": "abc123def456...",   # ← this authenticates the request
    "event_action": "trigger",
    ...
  }'
```
The routing_key comes from the PagerDuty Service Integration (pagerduty_service_integration). It's unique per integration and acts like an API key.

🔐 No bearer token, OAuth, or API key headers needed — just the routing key.

⚙️ 2. REST API v2 — for managing users, teams, services, etc.
This API does require authentication, and you'd use it in scripts that:

Move users between teams

Rotate on-call schedules

Fetch or update metadata

✅ Authentication method: Authorization: Token token=<API_KEY>

```bash
curl -X GET "https://api.pagerduty.com/users" \
  -H "Authorization: Token token=YOUR_PAGERDUTY_API_KEY" \
  -H "Accept: application/vnd.pagerduty+json;version=2"

```
You can create a user API token in your PagerDuty UI under:
User Icon > My Profile > User Settings > Create API User Token

| API               | Used For                      | Auth Method                |
| ----------------- | ----------------------------- | -------------------------- |
| **Events API v2** | Triggering alerts/incidents   | `routing_key`              |
| **REST API v2**   | Managing users/teams/services | `Authorization: Token ...` |
