##############################################################################
# Provider
##############################################################################
provider "squadcast" {
  api_key = var.squadcast_token
}

variable "squadcast_token" {}

##############################################################################
# Locals – same structure you used before
##############################################################################
locals {
  teams = ["InfraOps", "ShopStack", "FinGuard", "Shipit"]

  dummy_users = {
    InfraOps = ["InfraOps Engineer1", "InfraOps Engineer2", "InfraOps Engineer3"]
    ShopStack = ["ShopStack Engineer1", "ShopStack Engineer2", "ShopStack Engineer3"]
    FinGuard = ["FinGuard Engineer1", "FinGuard Engineer2", "FinGuard Engineer3"]
    Shipit   = ["Shipit Engineer1",  "Shipit Engineer2",  "Shipit Engineer3"]
  }

  real_users = {
    "AllTeams Engineer1" = {
      email = "janusz.gryszko@gmail.com"
      phone = "+4368184038262"
    }
    "AllTeams Engineer2" = {
      email = "gryszko@hotmail.com"
      phone = "+4369918108730"
    }
    "AllTeams Engineer3" = {
      email = "janusz.gryszko@redcare-pharmacy.com"
      phone = "+4368181396055"
    }
  }

  dummy_email = "imtoolpoc@gmail.com"
}

##############################################################################
# Users
##############################################################################

resource "squadcast_user" "dummy" {
  for_each = merge(flatten([
    for team, users in local.dummy_users : {
      for idx, user in users :
      "${team}_${idx}" => { name = user, team = team }
    }
  ])...)

  full_name = each.value.name
  email     = local.dummy_email
  role      = "User"
}

resource "squadcast_user" "real" {
  for_each = local.real_users

  full_name = each.key
  email     = each.value.email
  phone     = each.value.phone
  role      = "User"
}

##############################################################################
# Teams (Squads)
##############################################################################
resource "squadcast_team" "teams" {
  for_each   = toset(local.teams)
  name       = each.key
  is_default = false
}

##############################################################################
# Attach dummy users to their teams
##############################################################################
resource "squadcast_team_member" "dummy_members" {
  for_each = {
    for k, u in squadcast_user.dummy :
    k => { team = split("_", k)[0], user_id = u.id }
  }

  team_id = squadcast_team.teams[each.value.team].id
  user_id = each.value.user_id
  role    = "Member"
}

##############################################################################
# Schedules (Rotation) – one‑per‑team
##############################################################################
resource "squadcast_schedule" "schedules" {
  for_each   = toset(local.teams)

  name       = "${each.key} On‑Call"
  timezone   = "UTC"
  # 24 h daily rotation, primary only
  rotation {
    name       = "primary"
    start_time = "2025-01-01T00:00:00Z"
    shift_length = 1
    shift_unit = "days"
    users = [
      for k,u in squadcast_user.dummy :
      u.id if split("_", k)[0] == each.key
    ]
  }
}

##############################################################################
# Escalation Policies
##############################################################################
resource "squadcast_escalation_policy" "policies" {
  for_each  = toset(local.teams)

  name      = "${each.key} Escalation"
  step {
    delay       = 10   # minutes
    schedule_id = squadcast_schedule.schedules[each.key].id
  }
  team_id = squadcast_team.teams[each.key].id
}

##############################################################################
# Services
##############################################################################
locals {
  service_team = {
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

resource "squadcast_service" "svc" {
  for_each = local.service_team

  name                  = each.key
  escalation_policy_id  = squadcast_escalation_policy.policies[each.value].id
  team_id               = squadcast_team.teams[each.value].id
  type                  = "application"
}

##############################################################################
# Alert Sources (Events API v2) – integration key per service
##############################################################################
resource "squadcast_alert_source" "src" {
  for_each   = squadcast_service.svc

  name       = "API‑${each.key}"
  service_id = each.value.id
  type       = "api"
}

##############################################################################
# Event Rules – severity + tier mapping (Squadcast Webhook Filters)
##############################################################################
resource "squadcast_event_rule_set" "router" {
  name = "demo‑tier‑router"

  dynamic "rule" {
    for_each = [
      # phone: tier1 critical|high
      { tier = "tier1", severity = ["critical", "high"], tag = "phone" },

      # push: tier1 medium
      { tier = "tier1", severity = ["medium"], tag = "push" },

      # email: tier1 low
      { tier = "tier1", severity = ["low"], tag = "email" },

      # email: tier2 medium|low
      { tier = "tier2", severity = ["medium", "low"], tag = "email" },

      # email: all of tier3
      { tier = "tier3", severity = ["critical","high","medium","low"], tag = "email" },
    ]
    content {
      name        = "${rule.value.tier}-${rule.value.tag}"
      description = "Route ${rule.value.severity} of ${rule.value.tier} ⇒ tag:${rule.value.tag}"
      filter      = jsonencode({
        matchers = [
          { field = "custom_details.service_tier", operator = "equals", value = rule.value.tier },
          { field = "severity", operator         = "in",     value = rule.value.severity }
        ]
      })
      action {
        type  = "tag"
        value = [rule.value.tag]   # tag added to alert -> Squadcast notification rules can map tag→channel
      }
    }
  }
}
