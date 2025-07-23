import json, os, requests, sys
from typing import List, Tuple

# ── Configuration via environment variables ──────────────────────────────────
PAGERDUTY_TOKEN: str = (
    os.getenv("PAGERDUTY_API_TOKEN")     # set in docker‑compose.yml
    or os.getenv("API_TOKEN")         # fallback if kept from old naming
)
if not PAGERDUTY_TOKEN:
    sys.exit("❌  PAGERDUTY_API_TOKEN not set")

# Choose the right regional host automatically
API_REGION = "eu"
API_BASE   = f"https://api.eu.pagerduty.com"

HEADERS = {
    "Authorization": f"Token token={PAGERDUTY_TOKEN}",
    "Accept": "application/vnd.pagerduty+json;version=2",
    "Content-Type": "application/json",
    "User-Agent": "otel-demo-tests/1.0",
}

# Real & dummy users come from env so CI can override without code edits
REAL_EMAILS: List[str] = os.getenv("PD_REAL_EMAILS").split(",")  # email,email,email
REAL_USERS:  List[str] = os.getenv("PD_REAL_USERS" ).split(",")  # id,id,id
DUMMY_USERS: List[str] = os.getenv("PD_DUMMY_USERS").split(",")

# Map a logical test‑suite key → PagerDuty team ID
TEAM_MAP = json.loads(os.getenv("PD_TEAM_MAP", "{}"))
# Example: export PD_TEAM_MAP='{"checkout":"PQR123","payment":"PQR456"}'

# ── Library functions ───────────────────────────────────────────────────────

def ensure_team_has_real_oncall(team_key: str) -> None:
    """
    • Remove REAL_USERS from any team they’re currently in.
    • Put DUMMY_USERS back into every other team.
    • Put REAL_USERS (in declared order) into the escalation policy of *team_key*.
    """
    if team_key not in TEAM_MAP:
        raise KeyError(f"Team key {team_key!r} not in PD_TEAM_MAP env var")

    target_team_id = TEAM_MAP[team_key]

    # Get every team we know about + its escalation policy ID
    teams = {key: _first_escalation_policy_id(tid) for key, tid in TEAM_MAP.items()}

    for key, ep_id in teams.items():
        desired_users = REAL_USERS if key == team_key else DUMMY_USERS
        _rewrite_escalation_policy(ep_id, desired_users)

def incident_team_and_engineer(incident_id: str) -> Tuple[str, str]:
    """
    Return (team_name, engineer_name) for the given incident.
    """
    r = requests.get(
        f"{API_BASE}/incidents/{incident_id}",
        headers=HEADERS,
        params={"include[]": ["teams", "assignments"]},
        timeout=10,
    )
    r.raise_for_status()
    inc = r.json()["incident"]

    team   = inc["teams"][0]["summary"]             if inc.get("teams") else "unknown"
    person = inc["assignments"][0]["assignee"]["summary"] if inc.get("assignments") else "unassigned"
    return team, person


def acknowledge_incident_as(team_id: str, engineer_name: str) -> str | None:
    """
    Acknowledge the most recent incident for *team_id* *on behalf of*
    *engineer_name*.  Returns the incident ID or None if nothing to ack.
    """
    inc_id = _incident_id_for_team(team_id)
    if not inc_id:
        return None

    user_id = _user_id_for(engineer_name)
    payload = {
        "incident": {
            "type": "incident_reference",
            "status": "acknowledged",
            "acknowledgement_reason": "auto‑ack from test",
        },
        "requester_id": user_id,
    }
    r = requests.put(
        f"{API_BASE}/incidents/{inc_id}",
        headers=HEADERS,
        json=payload,
        timeout=10,
    )
    r.raise_for_status()
    return inc_id

# ── Internal helpers ─────────────────────────────────────────────────────────

def _rewrite_escalation_policy(ep_id: str, user_ids: List[str]) -> None:
    rules = [
        {
            "escalation_delay_in_minutes": 5,
            "targets": [{"id": uid, "type": "user_reference"}],
        }
        for uid in user_ids
    ]
    payload = {"escalation_policy": {"escalation_rules": rules}}
    r = requests.put(f"{API_BASE}/escalation_policies/{ep_id}", json=payload, headers=HEADERS, timeout=10)
    r.raise_for_status()


def _incident_id_for_team(team_id: str) -> str | None:
    """Return the most recent triggered/acknowledged incident ID, or None."""
    inc = _latest_incident_for_team(team_id)
    return inc["id"] if inc else None


def _first_escalation_policy_id(team_id: str) -> str:
    r = requests.get(
        f"{API_BASE}/teams/{team_id}",
        headers=HEADERS,
        params={"include[]": "escalation_policies"},
        timeout=10,
    )
    r.raise_for_status()
    eps = r.json()["team"]["escalation_policies"]
    if not eps:
        raise RuntimeError(f"Team {team_id} has no escalation policy")
    return eps[0]["id"]

