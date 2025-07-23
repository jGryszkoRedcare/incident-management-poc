import os, requests, pytest, json

ROUTER = os.getenv("ROUTER", "").lower()

def export_pagerduty():
    token = os.getenv("API_TOKEN")
    if not token:
        pytest.skip("API_TOKEN not set")
    hdr = {
        "Authorization": f"Token token={token}",
        "Accept": "application/vnd.pagerduty+json;version=2",
        "User-Agent": "otel-demo-smoke/1.0",
    }
    data = requests.get(
        "https://api.pagerduty.com/services?limit=25", headers=hdr, timeout=10
    ).json()
    print(json.dumps(data, indent=2, sort_keys=True))
    assert data["services"], "PagerDuty returned zero services"

def export_squadcast():
    token = os.getenv("API_TOKEN")
    if not token:
        pytest.skip("API_TOKEN not set")
    # swap refresh→access (1‑hour token)
    access = requests.post(
        "https://auth.squadcast.com/oauth/token",
        json={"grant_type": "refresh_token", "refresh_token": token},
        timeout=10,
    ).json()["access_token"]
    hdr = {"Authorization": f"Bearer {access}", "Accept": "application/json"}
    data = requests.get(
        "https://api.squadcast.com/v3/services?limit=25", headers=hdr, timeout=10
    ).json()
    print(json.dumps(data, indent=2, sort_keys=True))
    assert data.get("data"), "Squadcast returned zero services"

@pytest.mark.smoke
def test_router_export():
    if ROUTER == "pagerduty":
        export_pagerduty()
    elif ROUTER == "squadcast":
        export_squadcast()
    else:
        pytest.fail(f"Unsupported ROUTER={ROUTER!r}")
