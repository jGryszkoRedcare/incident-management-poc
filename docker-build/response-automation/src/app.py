"""Response‑Automation Flask app.
Endpoints:
  /restart-service      → restarts a demo container
  /scale-service        → scales demo service to N replicas (best‑effort)
  /cleanup-prometheus   → deletes TSDB blocks
"""
import os
from typing import Tuple

from flask import Flask, request, jsonify
from rich import print
import subprocess

# Docker python SDK
import docker
from tenacity import retry, stop_after_attempt, wait_fixed

from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk._logs import LoggingHandler, LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
import logging   # stdlib

app = Flask(__name__)

# ---- one‑time OTel setup ----
resource = Resource.create({"service.name": "response-automation"})
trace.set_tracer_provider(TracerProvider(resource=resource))
metrics.set_meter_provider(MeterProvider(resource=resource,
    metric_readers=[PeriodicExportingMetricReader(OTLPMetricExporter())]))
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter())
)

log_provider = LoggerProvider(resource=resource)
log_provider.add_log_record_processor(
    BatchLogRecordProcessor(OTLPLogExporter())
)
LoggingInstrumentor().instrument(set_logging_provider=log_provider)

# Optional: replace Flask’s default logger so everything funnels through OTel
logging.basicConfig(level=logging.INFO, handlers=[LoggingHandler(level=logging.INFO)])

FlaskInstrumentor().instrument_app(app)

# -----------------------------

client = docker.DockerClient(base_url="unix://var/run/docker.sock")

# ────────────────────────────────────────────────────────────────
# helpers
# ────────────────────────────────────────────────────────────────

def _find_containers(service_name: str):
    """Return all containers of a compose service (name starts with service)."""
    return [c for c in client.containers.list(all=True) if c.name.startswith(service_name)]

@retry(stop=stop_after_attempt(5), wait=wait_fixed(2))
def _restart_service(service: str) -> Tuple[bool, str]:
    containers = _find_containers(service)
    if not containers:
        return False, f"Service {service} not found"
    for cont in containers:
        print(f"[yellow]Restarting {cont.name}…[/]")
        cont.restart(timeout=10)
    return True, f"Restarted {len(containers)} container(s) for {service}"


def _scale_service(service: str, replicas: int) -> Tuple[bool, str]:
    """Best‑effort scaling using docker compose CLI.
    Requires docker CLI & compose v2 available in the host namespace mounted
    into this container (common when /usr/bin/docker is shared).
    """
    if replicas < 1:
        return False, "replicas must be >= 1"
    try:
        print(f"[cyan]Scaling {service} to {replicas} replicas…[/]")
        # Note: docker compose v2 syntax; using subprocess as Compose is not in SDK
        subprocess.check_call(["docker", "compose", "up", "-d", "--scale", f"{service}={replicas}"])
        return True, "Scale command issued"
    except subprocess.CalledProcessError as exc:
        return False, f"Compose scale failed: {exc}"

# ────────────────────────────────────────────────────────────────
# routes
# ────────────────────────────────────────────────────────────────

@app.route("/health", methods=["GET"])
def health():
    return "ok", 200

@app.route("/restart-service", methods=["POST"])
def restart_service():
    payload = request.get_json(force=True)
    service = payload.get("component") or payload.get("service") or payload.get("service_name")
    if not service:
        return jsonify({"error": "No service name in payload"}), 400

    ok, msg = _restart_service(service)
    return jsonify({"message": msg}), 200 if ok else 500

@app.route("/scale-service", methods=["POST"])
def scale_service():
    data = request.get_json(force=True)
    service = data.get("service") or data.get("component")
    replicas = int(data.get("replicas", 2))
    if not service:
        return jsonify({"error": "service field required"}), 400
    ok, msg = _scale_service(service, replicas)
    return jsonify({"message": msg}), 200 if ok else 500

@app.route("/cleanup-prometheus", methods=["POST"])
def cleanup_prometheus():
    prometheus_url = os.getenv("PROMETHEUS_URL", "http://prometheus:9090")
    import requests
    resp = requests.post(
        f"{prometheus_url}/api/v1/admin/tsdb/delete_series",
        params={"match[]": "{__name__=~'.+'}"},
    )
    print(f"[blue]Prometheus cleanup status {resp.status_code}")
    return jsonify({"status": resp.status_code}), resp.status_code

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)