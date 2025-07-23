#####################################################################
# Extra provider – points at your running Grafana behind ngrok
#####################################################################
provider "grafana" {
  url      = "http://grafana.impoc.ngrok.app:3000"
  insecure_skip_verify = true   # http behind ngrok TLS
  # no auth = … here ─ provider picks up $GRAFANA_AUTH
}

#####################################################################
# Use the PagerDuty routing key you already created
#####################################################################
resource "grafana_contact_point" "pagerduty_cp" {
  name = "PagerDuty‑All"

  type = "pagerduty"

  settings_json = jsonencode({
    integrationKey = pagerduty_service_integration.integrations["frontend"].integration_key
    # Optional static fields:
    # severity      = "{{ .Labels.severity | default \"error\" }}"
    # class         = "grafana‑alert"
    # component     = "{{ .Annotations.panel }}"
  })
}

#####################################################################
# Make every alert go to that contact point
#####################################################################
resource "grafana_notification_policy" "root" {
  # root policy has empty matcher lists
  contact_point_ids = [grafana_contact_point.pagerduty_cp.contact_point_id]
}
