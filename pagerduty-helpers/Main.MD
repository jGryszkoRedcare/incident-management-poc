# Test Alert
Send the test alert after everything was provisioned by terraform. PagerDuty will evaluate:

- Which service it matches (from routing key and orchestration rules)
- Who’s on-call for that service
- What notification method should be used (based on your rules)

# Alert Format

{
  "routing_key": "frontend",          // the exact service name
  "payload": {
    "severity": "critical",           // one of: critical, high, medium, low
    "custom_details": {
      "service_tier": 1             // one of: 1, 2, 3
    }
  }
}