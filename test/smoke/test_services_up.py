import time
import requests
import pytest

# Service → health‑check URL
SERVICES = {
    "grafana":    "http://grafana:3000/api/health",          # 200 = OK :contentReference[oaicite:0]{index=0}
    "opensearch": "http://opensearch:9200/_cluster/health", # 200 = any colour :contentReference[oaicite:1]{index=1}
    "prometheus": "http://prometheus:9090/-/healthy",       # always 200 when up :contentReference[oaicite:2]{index=2}
}

def wait_until_healthy(url, timeout_s=60, interval_s=3):
    """Poll *url* until it returns HTTP 200‑399 or time runs out."""
    end = time.monotonic() + timeout_s
    while time.monotonic() < end:
        try:
            r = requests.get(url, timeout=5)
            if 200 <= r.status_code < 400:
                return r
        except requests.RequestException:
            pass
        time.sleep(interval_s)
    raise RuntimeError(f"{url} never became healthy within {timeout_s}s")

@pytest.mark.parametrize("service,url", SERVICES.items())
def test_service_health(service, url):
    res = wait_until_healthy(url)
    assert 200 <= res.status_code < 400, f"{service} unhealthy: {res.status_code}"
