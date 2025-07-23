# PagerDuty Terraform Stack for On-Call and Escalation

provider "pagerduty" {
  token = var.pagerduty_token
  service_region = "eu"
}

#####################
# Variables
#####################

variable "pagerduty_token" {}

#####################
# Users
#####################

locals {
  teams = ["InfraOps", "ShopStack", "FinGuard", "Shipit"]

  dummy_users = {
    "InfraOps" = ["InfraOps Engineer1", "InfraOps Engineer2", "InfraOps Engineer3"]
    "ShopStack" = ["ShopStack Engineer1", "ShopStack Engineer2", "ShopStack Engineer3"]
    "FinGuard" = ["FinGuard Engineer1", "FinGuard Engineer2", "FinGuard Engineer3"]
    "Shipit"   = ["Shipit Engineer1", "Shipit Engineer2", "Shipit Engineer3"]
  }

  real_users = {
    "AllTeams Engineer1" = {
      email      = "janusz.gryszko@gmail.com"
      job_title  = "OnCall AllTeams"
      phone      = "+4368184038262"
    }
    "AllTeams Engineer2" = {
      email      = "gryszko@hotmail.com"
      job_title  = "OnCall AllTeams"
      phone      = "+4369918108730"
    }
    "AllTeams Engineer3" = {
      email      = "janusz.gryszko@redcare-pharmacy.com"
      job_title  = "OnCall AllTeams"
      phone      = "+4368181396055"
    }
  }

  dummy_email = "imtoolpoc@gmail.com"
}

resource "pagerduty_user" "dummy_users" {
  for_each = merge(flatten([
    for team, users in local.dummy_users : {
      for idx, user in users : "${team}_${idx}" => {
        name  = user
        team  = team
      }
    }
  ])...)

  name      = each.value.name
  email     = local.dummy_email
  job_title = "Dummy"
}

resource "pagerduty_user" "real_users" {
  for_each = local.real_users

  name      = each.key
  email     = each.value.email
  job_title = each.value.job_title
}

resource "pagerduty_user_contact_method" "email" {
  for_each = local.real_users
  user_id  = pagerduty_user.real_users[each.key].id
  type     = "email_contact_method"
  address  = each.value.email
  label    = "Email"
}

resource "pagerduty_user_contact_method" "push" {
  for_each = local.real_users
  user_id  = pagerduty_user.real_users[each.key].id
  type     = "push_notification_contact_method"
  label    = "Push"
}

resource "pagerduty_user_contact_method" "phone" {
  for_each = local.real_users
  user_id      = pagerduty_user.real_users[each.key].id
  type         = "phone_contact_method"
  country_code = "43"
  address      = replace(each.value.phone, "+43", "")
  label        = "Mobile"
}

resource "pagerduty_user_notification_rule" "call_rule" {
  for_each = local.real_users
  user_id     = pagerduty_user.real_users[each.key].id
  start_delay_in_minutes = 0
  contact_method {
    type = "phone_contact_method"
    id   = pagerduty_user_contact_method.phone[each.key].id
  }
}

resource "pagerduty_user_notification_rule" "push_rule" {
  for_each = local.real_users
  user_id     = pagerduty_user.real_users[each.key].id
  start_delay_in_minutes = 0
  contact_method {
    type = "push_notification_contact_method"
    id   = pagerduty_user_contact_method.push[each.key].id
  }
}

resource "pagerduty_user_notification_rule" "email_rule" {
  for_each = local.real_users
  user_id     = pagerduty_user.real_users[each.key].id
  start_delay_in_minutes = 0
  contact_method {
    type = "email_contact_method"
    id   = pagerduty_user_contact_method.email[each.key].id
  }
}

#####################
# Teams
#####################

resource "pagerduty_team" "teams" {
  for_each = toset(local.teams)
  name     = each.key
}

#####################
# Team Memberships (Dummy Users Only)
#####################

resource "pagerduty_team_membership" "memberships" {
  for_each = {
    for key, user in pagerduty_user.dummy_users :
    key => {
      user_id = user.id
      team    = split("_", key)[0]
    }
  }

  user_id = each.value.user_id
  team_id = pagerduty_team.teams[each.value.team].id
}

#####################
# Schedules
#####################

resource "pagerduty_schedule" "team_schedules" {
  for_each = toset(local.teams)

  name      = "${each.key} On-Call Schedule"
  time_zone = "UTC"

  layer {
    name                         = "Primary"
    start                        = "2025-01-01T00:00:00-00:00"
    rotation_virtual_start       = "2025-01-01T00:00:00-00:00"
    rotation_turn_length_seconds = 86400

    users = [for k, u in pagerduty_user.dummy_users : u.id if split("_", k)[0] == each.key]
  }
}

#####################
# Escalation Policies
#####################

resource "pagerduty_escalation_policy" "team_policies" {
  for_each = toset(local.teams)

  name      = "${each.key} Escalation Policy"
  num_loops = 2

  escalation_rules {
    escalation_delay_in_minutes = 10
    target {
      type = "schedule_reference"
      id   = pagerduty_schedule.team_schedules[each.key].id
    }
  }

  teams = [pagerduty_team.teams[each.key].id]
}

#####################
# Services per Team
#####################

locals {
  service_team_mapping = {
    kafka            = "InfraOps"
    postgres         = "InfraOps"
    grafana          = "InfraOps"
    otel-collector   = "InfraOps"
    flagd            = "InfraOps"
    flagd-ui         = "InfraOps"

    frontend         = "ShopStack"
    frontend-proxy   = "ShopStack"
    cart             = "ShopStack"
    product-catalog  = "ShopStack"
    image-provider   = "ShopStack"
    recommendation   = "ShopStack"

    payment          = "FinGuard"
    fraud-detection  = "FinGuard"
    currency         = "FinGuard"
    accounting       = "FinGuard"

    shipping         = "Shipit"
    quote            = "Shipit"
  }
}

resource "pagerduty_service" "services" {
  for_each = local.service_team_mapping

  name                    = each.key
  auto_resolve_timeout    = 14400
  acknowledgement_timeout = 600
  escalation_policy       = pagerduty_escalation_policy.team_policies[each.value].id
  alert_creation          = "create_alerts_and_incidents"
}

resource "pagerduty_service_integration" "integrations" {
  for_each = pagerduty_service.services

  name    = "CloudWatch Events"
  type    = "events_api_v2_inbound_integration"
  service = each.value.id
}

#####################
# Event Orchestration Based on Metadata
#####################

resource "pagerduty_event_orchestration" "main" {
  name = "Main Orchestration"
}

resource "pagerduty_event_orchestration_router" "router" {
  orchestration = pagerduty_event_orchestration.main.id

  rule {
    condition {
      expression = "event.severity == \"critical\" && event.custom_details.service_tier == \"tier1\""
    }
    actions {
      route_to = pagerduty_service.services["frontend"].id
      annotate = "Phone Call - Tier1 Critical"
    }
  }

  rule {
    condition {
      expression = "event.severity == \"high\" && event.custom_details.service_tier == \"tier1\""
    }
    actions {
      route_to = pagerduty_service.services["frontend"].id
      annotate = "Phone Call - Tier1 High"
    }
  }

  rule {
    condition {
      expression = "event.severity == \"medium\" && event.custom_details.service_tier == \"tier1\""
    }
    actions {
      route_to = pagerduty_service.services["frontend"].id
      annotate = "Push - Tier1 Medium"
    }
  }

  rule {
    condition {
      expression = "event.severity == \"low\" && event.custom_details.service_tier == \"tier1\""
    }
    actions {
      route_to = pagerduty_service.services["frontend"].id
      annotate = "Email - Tier1 Low"
    }
  }

  rule {
    condition {
      expression = "event.severity == \"medium\" && event.custom_details.service_tier == \"tier2\""
    }
    actions {
      route_to = pagerduty_service.services["frontend"].id
      annotate = "Email - Tier2 Medium"
    }
  }

  rule {
    condition {
      expression = "event.severity == \"low\" && event.custom_details.service_tier == \"tier2\""
    }
    actions {
      route_to = pagerduty_service.services["frontend"].id
      annotate = "Email - Tier2 Low"
    }
  }

  rule {
    condition {
      expression = "event.custom_details.service_tier == \"tier3\""
    }
    actions {
      route_to = pagerduty_service.services["frontend"].id
      annotate = "Email - Tier3 Any"
    }
  }
}

output "routing_keys" {
  value = {
    for k, v in pagerduty_service_integration.integrations : k => v.integration_key
  }
}
