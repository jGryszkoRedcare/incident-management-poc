provider "grafana" {
  url                   = "http://grafana.impoc.ngrok.app:3000"
  insecure_skip_verify  = true          # http behind ngrok TLS tunnel
}

##############################################################################
# Grafana contact point + root notification policy
##############################################################################
resource "grafana_contact_point" "pagerduty_cp" {
  name = "PagerDuty‑All"

  pagerduty {
    integration_key = pagerduty_service_integration.integrations["frontend"].integration_key
  }
}

resource "grafana_notification_policy" "root" {
  group_by      = []
  contact_point = grafana_contact_point.pagerduty_cp.id
}
