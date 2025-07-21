#### Recommendation for a PoC roadmap

- Phase 0 – pipeline smoke‑test. Use otelgen or telemetrygen to push a few spans/metrics into Mimir/Tempo so you know the plumbing is correct.

- Phase 1 – happy‑path demo. Bring up the OTel demo or your own two‑service skeleton; write a tiny chaos script that injects latency and exceptions so you can demo incident creation / routing.

- Phase 2 – scale & corner‑cases. Keep the synthetic generator running in the background to spam high‑cardinality data while the micro‑services reproduce realistic fault patterns.

This hybrid approach lets you keep the ease of idea #1 while adding the fidelity of idea #2 only where it actually benefits the PoC.
	
	
What you don’t give up by staying on Compose
Capability	Compose notes
Full OTLP pipeline	Each container can export traces/metrics/logs via OTEL_EXPORTER_OTLP_ENDPOINT=http://collector:4317; the Collector, Tempo and Mimir run as sibling services.
Service‑level scrapes	Prometheus ≥ 2.41 has native Docker service discovery (docker_sd_configs); it can scrape every container on the host without manual target lists. 
Stack Overflow
Context propagation across calls	As long as each client library propagates the W3C TraceContext headers, distributed spans work exactly as they do on Kubernetes.
Scaling for quick tests	You can still run multiple replicas with docker compose up --scale orderservice=3; health probes and ingress simulation can be scripted.

Horizontal autoscaling	Compose has no auto‑HPA equivalent—so any incident scenarios that rely on autoscaler events can’t be reproduced directly. (Manual --scale works for load tests.) 

Step	What to do
1 · Use the demo as a template	git clone https://github.com/open-telemetry/opentelemetry-demo && docker compose up -d brings up a realistic shop with traces, logs and metrics in ~60 s. Swap Grafana Tempo → Mimir back‑end if that’s what your incident router will ingest. 
GitHub
2 · Inject faults deterministically	Add a small flag or env var to each service (e.g. FAIL_RATE=0.2, EXTRA_LATENCY_MS=500) so you can toggle chaos from outside rather than editing code.
3 · Expose Docker metadata as labels	In prometheus.yml:

scrape_configs:

```markdown
job_name: 'docker-services'
docker_sd_configs:

- host: unix:///var/run/docker.sock
  relabel_configs:

- source_labels: [__meta_docker_container_label_com_docker_compose_service]
  target_label: service
```

This gives you a clean `service=<compose_service>` label in every time‑series/spans. |
| **4 · Collector resource detectors** | Enable the *docker* resource detector in your OTel Collector so each span has `container.id`, `container.image.name`, etc. That partially compensates for missing k8s.* attributes. |
| **5 · Keep one synthetic generator around** | Tools like `otelgen` are handy for stress‑testing cardinality or throughput without launching dozens more containers. |

### Bottom line

For a *local* PoC whose goal is “Does my incident router handle distributed traces, metrics and alerting rules?”, **Docker Compose is the simplest, lowest‑friction path**.  
The only real limitations are:

1. **No Kubernetes‑specific metadata or autoscaling events**—adjust alert rules/dashboards accordingly.  
2. **Single‑node scope**—you can’t test cross‑cluster or node‑failure scenarios.  

If those two gaps are acceptable (and they usually are for an early proof‑of‑concept), go ahead and run everything via `docker compose up`. You can always lift the same containers into a k8s manifest later if you need production‑grade scale‑out tests.
::contentReference[oaicite:5]{index=5}

***Example prometheus alert rule with team assignment***

```yaml
# prometheus/rules/services.rules.yml
groups:
  - name: service-errors
    rules:
      - alert: HighErrorRate
        expr: rate(http_server_errors_total[5m]) > 0.05
        for: 2m
        labels:
          severity: page
          service: checkout
          team: payments
        annotations:
          summary: "{{ $labels.service }} 5xx is >5 %."
```


## Classic Prometheus / Alertmanager → PagerDuty

 - If you prefer the “pure Prometheus” route, drop the official Alertmanager image into your compose file and add a minimal alertmanager.yml:
  
```yaml
route:
  group_by: [alertname,service]
  routes:
    - matchers:
        - team="payments"
      receiver: pagerduty-payments
    - matchers:
        - team="orders"
      receiver: pagerduty-orders

receivers:
  - name: pagerduty-payments
    pagerduty_configs:
      - routing_key: ${PD_PAYMENTS}
        send_resolved: true
  - name: pagerduty-orders
    pagerduty_configs:
      - routing_key: ${PD_ORDERS}
        send_resolved: true
```
***The PagerDuty section is exactly what the Grafana blog’s walk‑through shows***

#### Grafana Labs

- Pros
  - Familiar to anyone coming from Kubernetes or a Prometheus‑native stack.
  - You can keep one Alertmanager per team if you want strict isolation.

- Cons
  - Extra container + config management.
  - PagerDuty schedules live outside Grafana, so demoing “who’s on call” requires switching UIs.

```markdown
        expr: rate(http_server_errors_total[5m]) > 0.05
        for: 2m
        labels:
          severity: page
          service: checkout
          team: payments
        annotations:
          summary: "{{ $labels.service }} 5xx is >5 %."
```


### Prosnothing new to deploy
- Nothing new to deploy
- Grafana’s UI lets you attach multiple schedules to one contact point.

### Cons
- You still need Prometheus or Grafana‑level alert rules for every service.
- Escalations beyond PagerDuty (Slack, SMS) live in PagerDuty, not Grafana.

3 · Classic Prometheus / Alertmanager → PagerDuty
If you prefer the “pure Prometheus” route, drop the official Alertmanager image into your compose file and add a minimal alertmanager.yml:

2 · Fastest path—Grafana OSS → PagerDuty (no extra containers)
In PagerDuty create a Service → Events API v2 integration and copy the integration key.

In Grafana: Alerts & IRM → Alerting → Contact points → +Add → PagerDuty and paste the key. 
Grafana Labs

Under Notification policies add rules like Match “team=payments” → contact point “PD‑Payments”.

