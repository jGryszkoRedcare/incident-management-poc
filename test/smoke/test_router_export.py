"""
Smoke‑test: export & print the key objects from the incident router
         (services, teams, users, memberships).

Env vars required
  ROUTER=pagerduty | squadcast
  API_TOKEN=<account token>              # PagerDuty: REST v2 “API Access Key”
                                         # Squadcast: Personal Refresh Token
"""

import os, time, json, requests, pytest
from pprint import pprint

ROUTER = os.getenv("ROUTER", "").lower()
API_TOKEN = os.getenv("API_TOKEN") or os.getenv("PAGERDUTY_API_TOKEN")

# -----------------------------------------------------------------------------
# PagerDuty helpers
# -----------------------------------------------------------------------------
def _pd_get(path: str, params=None):
    hdr = {
        "Authorization": f"Token token={API_TOKEN}",
        "Accept": "application/vnd.pagerduty+json;version=2",
        "User-Agent": "otel-demo-smoke/1.1",
    }
    r = requests.get(f"https://api.eu.pagerduty.com{path}",  # use .com for US
                     headers=hdr, params=params, timeout=10)
    r.raise_for_status()
    return r.json()

def export_pagerduty():
    print("\n—— PagerDuty export ——————————————————————————————")

    services = _pd_get("/services", {"limit": 100})["services"]
    teams    = _pd_get("/teams",    {"limit": 100})["teams"]
    users    = _pd_get("/users",    {"limit": 100})["users"]

    # memberships: team → [user names]
    memberships = {}
    for t in teams:
        mids = _pd_get(f"/teams/{t['id']}/members")["members"]
        memberships[t["summary"]] = [m["user"]["summary"] for m in mids]

    _pretty_block("services", services)
    _pretty_block("teams",    teams)
    _pretty_block("users",    users)
    _pretty_block("memberships", memberships)

    assert services and teams and users, "PagerDuty export returned empty lists"

# -----------------------------------------------------------------------------
# Squadcast helpers
# -----------------------------------------------------------------------------
def _sc_headers():
    # Refresh‑token → 1 h access token
    r = requests.post("https://auth.squadcast.com/oauth/token",
                      json={"grant_type": "refresh_token",
                            "refresh_token": API_TOKEN},
                      timeout=10)
    r.raise_for_status()
    access = r.json()["access_token"]
    return {"Authorization": f"Bearer {access}", "Accept": "application/json"}

def _sc_get(path: str, params=None):
    r = requests.get(f"https://api.squadcast.com/v3{path}",
                     headers=_sc_headers(), params=params, timeout=10)
    r.raise_for_status()
    return r.json()

def export_squadcast():
    print("\n—— Squadcast export ——————————————————————————————")

    services = _sc_get("/services")["data"]
    squads   = _sc_get("/squads")["data"]
    users    = _sc_get("/users")["data"]

    memberships = {}
    for s in squads:
        members = _sc_get(f"/squads/{s['id']}/members")["data"]
        memberships[s["name"]] = [m["user"]["name"] for m in members]

    _pretty_block("services", services)
    _pretty_block("squads",   squads)
    _pretty_block("users",    users)
    _pretty_block("memberships", memberships)

    assert services and squads and users, "Squadcast export returned empty lists"

# -----------------------------------------------------------------------------
# tiny helpers
# -----------------------------------------------------------------------------
def _pretty_block(label, data):
    print(f"\n### {label}\n{json.dumps(data, indent=2, sort_keys=True)}")

# -----------------------------------------------------------------------------
# pytest entry‑point
# -----------------------------------------------------------------------------
@pytest.mark.smoke
def test_router_export():
    if not API_TOKEN:
        pytest.skip("API_TOKEN not set")

    if ROUTER == "pagerduty":
        export_pagerduty()
    elif ROUTER == "squadcast":
        export_squadcast()
    else:
        pytest.fail(f"Unsupported ROUTER={ROUTER!r}")
