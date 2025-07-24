##############################################################################
# Providers
##############################################################################
terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 2.3"
    }
    pagerduty = {
      source  = "pagerduty/pagerduty"
      version = "~> 2.12"
    }
  }
}