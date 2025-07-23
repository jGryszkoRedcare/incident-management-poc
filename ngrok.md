# NGROK Configuration for Multiple Subdomains

Edit on Linux or macOS:
~/.config/ngrok/ngrok.yml

Or on Windows:
%HOMEPATH%\.config\ngrok\ngrok.yml

```yaml
# ngrok.yml
authtoken: ${NGROK_AUTHTOKEN}    # paste yours or export as env var

version: 2
tunnels:
  grafana:
    proto: http
    addr: 3000                  # container/host port
    domain: grafana.impoc.ngrok.app

  prometheus:
    proto: http
    addr: 9090
    domain: prometheus.impoc.ngrok.app

  response-automation:
    proto: http
    addr: 5000
    domain: response-automation.impoc.ngrok.app

```