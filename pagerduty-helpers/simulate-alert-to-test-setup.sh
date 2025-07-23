#!/usr/bin/env bash

curl -X POST https://events.pagerduty.com/v2/enqueue \
  -H "Content-Type: application/json" \
  -d '{
    "routing_key": "payment",
    "event_action": "trigger",
    "payload": {
      "summary": "Test alert for shipping service",
      "source": "shipping-api",
      "severity": "critical",
      "custom_details": {
        "service_tier": 1
      }
    }
  }'
