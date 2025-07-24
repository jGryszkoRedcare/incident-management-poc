##############################################################################
# Grafana contact‑point
##############################################################################
provider "grafana" {
  url  = "http://grafana.impoc.ngrok.app:3000"
  insecure_skip_verify = true
}

resource "grafana_contact_point" "squadcast_cp" {
  name = "Squadcast‑All"
  type = "squadcast"

  settings_json = jsonencode({
    apiKey = squadcast_alert_source.src["frontend"].api_key
    # ^ any integration key works – choose frontend as an example
  })
}

resource "grafana_notification_policy" "root" {
  contact_point_ids = [grafana_contact_point.squadcast_cp.contact_point_id]
}

##############################################################################
# Outputs – integration keys
##############################################################################
output "routing_keys" {
  value = {
    for k,v in squadcast_alert_source.src : k => v.api_key
  }
}
