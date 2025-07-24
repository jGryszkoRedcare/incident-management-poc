
provider "pagerduty" {
  token          = var.pagerduty_token
  service_region = "eu"
}

variable "pagerduty_token" {}


##############################################################################
# PagerDuty users and contact methods
##############################################################################
locals {
  teams = ["InfraOps", "ShopStack", "FinGuard", "Shipit"]

  # ── dummy users ------------------------------------------------------------
  dummy_users = {
    "InfraOps"  = ["InfraOps Engineer1", "InfraOps Engineer2", "InfraOps Engineer3"]
    "ShopStack" = ["ShopStack Engineer1", "ShopStack Engineer2", "ShopStack Engineer3"]
    "FinGuard"  = ["FinGuard Engineer1", "FinGuard Engineer2", "FinGuard Engineer3"]
    "Shipit"    = ["Shipit Engineer1",   "Shipit Engineer2",   "Shipit Engineer3"]
  }

  dummy_pairs = flatten([
    for team, users in local.dummy_users : [
      for idx, user in users : {
        key   = "${team}_${idx}"
        value = user
      }
    ]
  ])

  dummy_users_flat = {
    for pair in local.dummy_pairs : pair.key => pair.value
  }

  # ── real users -------------------------------------------------------------
  real_users = {
    "Janusz Gryszko" = {
      email = "janusz.gryszko@redcare-pharmacy.com"
      phone = "+4368184038262"
    }
    "Eduardo Galvan" = {
      email = "Eduardo.Galvan@redcare-pharmacy.com"
      phone = "+4368181396055"
    }
    "Daniel Krones" = {
      email = "Daniel.Krones@redcare-pharmacy.com"
      phone = "+4915114934124"
    }
  }

  # keep everyone *except* Janusz
  real_users_filtered = {
    for name, attrs in local.real_users :
    name => attrs
    if attrs.email != "janusz.gryszko@redcare-pharmacy.com"
  }

  dummy_email_prefix = "imtoolpoc"

   # If your plan *doesn’t* support low‑urgency, just set this var to false
  # urgencies = ["high", "low"]
   urgencies = ["low"]

  # Cartesian product: every user × every urgency
  user_urgency_matrix = flatten([
    for user_key in keys(local.real_users_filtered) : [
      for urgency in local.urgencies : {
        user_key = user_key
        urgency  = urgency
      }
    ]
  ])

  # Turn that list into a map so we can use it in for_each
  # Key must be unique per element → "{user}-{urgency}"
  user_urgency_map = {
    for combo in local.user_urgency_matrix :
    "${combo.user_key}-${combo.urgency}" => combo
  }
}


##############################################################################
# Dummy PagerDuty users
##############################################################################
resource "pagerduty_user" "dummy_users" {
  for_each = local.dummy_users_flat

  name      = each.value
  email     = "${local.dummy_email_prefix}_${each.key}@redcare-pharmacy.com"
  job_title = "Dummy Engineer ${each.key}"
}

##############################################################################
# Real PagerDuty users (filtered)
##############################################################################
resource "pagerduty_user" "real_users" {
  for_each = local.real_users_filtered

  name      = each.key
  email     = each.value.email
  job_title = "On‑Call Engineer"
}

##############################################################################
# Contact methods ------------------------------------------------------------
resource "pagerduty_user_contact_method" "email" {
  for_each = local.real_users_filtered
  user_id  = each.key
  type     = "email_contact_method"
  address  = each.value.email
  label    = "Email"
}
/*
resource "pagerduty_user_contact_method" "push" {
  for_each = local.real_users_filtered
  user_id  = pagerduty_user.real_users[each.key].id
  type     = "push_notification_contact_method"
  address  = "device"             # required in provider >= 2.13
  label    = "Push"
}

resource "pagerduty_user_contact_method" "phone" {
  for_each     = local.real_users_filtered
  user_id      = pagerduty_user.real_users[each.key].id
  type         = "phone_contact_method"
  label        = "Mobile"
  country_code = "43"
  address      = replace(each.value.phone, "+43", "")
}
*/

##############################################################################
# Notification rules (map syntax) -------------------------------------------
/* resource "pagerduty_user_notification_rule" "call_rule" {
  for_each               = local.real_users_filtered
  user_id                = pagerduty_user.real_users[each.key].id
  start_delay_in_minutes = 0
  urgency                = "high"

  contact_method = {
    type = "phone_contact_method"
    id   = pagerduty_user_contact_method.phone[each.key].id
  }
} */

/* resource "pagerduty_user_notification_rule" "push_rule" {
  for_each               = local.real_users_filtered
  user_id                = pagerduty_user.real_users[each.key].id
  start_delay_in_minutes = 0
  urgency                = "high"

  contact_method = {
    type = "push_notification_contact_method"
    id   = pagerduty_user_contact_method.push[each.key].id
  }
} */

resource "pagerduty_user_notification_rule" "email_rule" {
  for_each               = local.user_urgency_map

  user_id                = pagerduty_user.real_users[each.value.user_key].id
  urgency                = each.value.urgency          # "high" or "low"
  start_delay_in_minutes = 0

  contact_method = {
    type = "email_contact_method"
    id   = pagerduty_user_contact_method.email[each.value.user_key].id
  }
}


##############################################################################
# Teams, memberships, schedules, escalation policies
##############################################################################
resource "pagerduty_team" "teams" {
  for_each = toset(local.teams)
  name     = each.key
}

resource "pagerduty_team_membership" "memberships" {
  for_each = {
    for key, user in pagerduty_user.dummy_users :
    key => { user_id = user.id, team = split("_", key)[0] }
  }
  user_id = each.value.user_id
  team_id = pagerduty_team.teams[each.value.team].id
}

resource "pagerduty_schedule" "team_schedules" {
  for_each  = toset(local.teams)
  name      = "${each.key} On‑Call Schedule"
  time_zone = "Europe/Berlin"

  layer {
    name                         = "Primary"
    start                        = "2025-01-01T00:00:00Z"
    rotation_virtual_start       = "2025-01-01T00:00:00Z"
    rotation_turn_length_seconds = 86400
    users = [
      for k, u in pagerduty_user.dummy_users :
      u.id if split("_", k)[0] == each.key
    ]
  }
}

resource "pagerduty_escalation_policy" "team_policies" {
  for_each  = toset(local.teams)
  name      = "${each.key} Escalation Policy"
  num_loops = 2

  rule {                                # provider 2.x syntax
    escalation_delay_in_minutes = 10
    target {
      type = "schedule_reference"
      id   = pagerduty_schedule.team_schedules[each.key].id
    }
  }

  teams = [pagerduty_team.teams[each.key].id]
}

##############################################################################
# Services + integrations
##############################################################################
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
  name     = "Grafana Alerts"
  type     = "events_api_v2_inbound_integration"
  service  = each.value.id
}

##############################################################################
# (Optional) Event orchestration – commented until you migrate to v3 schema
##############################################################################
# resource "pagerduty_event_orchestration" "main" {
#   name = "Main Orchestration"
# }
#
# resource "pagerduty_event_orchestration_router" "router" {
#   orchestration = pagerduty_event_orchestration.main.id
#   # Router v2 schema requires set{} / catch_all{} blocks in provider 2.19+
# }

##############################################################################
# Outputs
##############################################################################
output "routing_keys" {
  value = {
    for k, v in pagerduty_service_integration.integrations :
    k => v.integration_key
  }
}
