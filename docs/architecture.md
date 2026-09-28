# Monitoring architecture

How metrics move across the 3-node fleet, and who can see what. Nodes are
named generically here (`node-1..3`); real hostnames and IPs live in the
gitignored inventory and `host_vars/` (`node_name` becomes the `node`
label on every scrape target, so dashboards show a hostname instead of a
scrape address).

## Core architecture

Everything is pull-based: exporters sit passively on every host, the one
Prometheus reaches out to all of them, and Grafana only ever talks to
Prometheus.

```mermaid
flowchart LR
  subgraph mac["your Mac"]
    ansible["Ansible<br/>provision.yml · deploy-apps.yml"]
  end

  subgraph n1["node-1 · monitoring host"]
    grafana["Grafana :3000"]
    prom["Prometheus :9090<br/>TSDB · 30 d"]
    kuma["Uptime Kuma :3001"]
    ne1["node_exporter :9100"]
    ca1["cAdvisor :8080"]
  end

  subgraph n2["node-2"]
    ne2["node_exporter :9100"]
    ca2["cAdvisor :8080"]
  end

  subgraph n3["node-3"]
    ne3["node_exporter :9100"]
    ca3["cAdvisor :8080"]
  end

  grafana -->|PromQL| prom
  prom -->|"pull /metrics · 15 s"| ne1
  prom --> ca1
  prom --> ne2
  prom --> ca2
  prom --> ne3
  prom --> ca3
  kuma -.->|HTTP checks| n2
  ansible -.->|"deploys stacks · renders<br/>prometheus.yml from inventory"| n1
  ansible -.-> n2
  ansible -.-> n3
```

Adding a host to the Ansible inventory adds its scrape targets on the next
deploy — the inventory is the service registry.

## Sequence: from scrape to rendered panel

Two independent rhythms: the scrape loop runs forever in the background;
the query path runs only when someone opens a dashboard. A scrape gap
shows up as a gap in the graph, never as an error.

```mermaid
sequenceDiagram
    participant B as Browser
    participant G as Grafana (:3000)
    participant P as Prometheus (:9090)
    participant E as Exporters (:9100 + :8080, ×3 hosts)

    Note over G: on start: loads provisioning/ from git —<br/>datasource (uid prometheus) + dashboards/*.json
    loop every 15 s
        P->>E: GET /metrics
        E-->>P: samples (counters + gauges)
        P->>P: append to TSDB (30 d)
    end
    B->>G: GET dashboard
    G->>P: POST /api/v1/query_range (PromQL)
    P->>P: evaluate over TSDB
    P-->>G: time-series JSON
    G-->>B: rendered panels
```

## Access paths: private vs public

The pipeline above is shared; what differs per audience is the way in.
Grafana (including the tokenized no-login Fleet Status URL) stays
LAN-only. The world-facing view is deliberately **off-fleet**
([../DECISION.md](../DECISION.md) #3): a status page must not share fate
with the thing it reports on — during a full-fleet power loss an
on-fleet page is unreachable, not red.

```mermaid
flowchart LR
  you["LAN user (you)"]
  world["public viewer<br/>(anyone)"]
  nodes["node-1..3"]

  subgraph g["Grafana · monitoring host (LAN only)"]
    private["all dashboards + admin<br/>(login required)"]
    fleet["Fleet Status<br/>/public-dashboards/&lt;token&gt;<br/>(no login)"]
  end

  subgraph off["off-fleet"]
    hc["Healthchecks.io<br/>one check per host"]
    status["portfolio /status page<br/>(GitHub Pages)"]
  end

  you -->|"LAN · credentials"| private
  you -->|"LAN · no credentials"| fleet
  nodes -->|"outbound ping · 1 min<br/>(heartbeat role)"| hc
  status -->|"public JSON badges"| hc
  world -->|HTTPS| status
```

Rules for the public path:

- Nothing inbound is exposed: hosts *push* heartbeats outward; the status
  page and its truth source are both hosted off-fleet, so a fleet-wide
  outage renders as red rows, not a dead link.
- Two kinds of Healthchecks URLs, never confused: **ping URLs are
  secrets** (anyone holding one can fake "up") and live in gitignored
  `host_vars/`; **badge URLs are public read-only** (revocable keys) and
  may be committed to the portfolio repo.
- Fleet Status keeps carrying only public-appropriate data (up/down,
  uptime, availability, CPU/memory %) so it *could* be exposed later, but
  today it is LAN-only; its share token can be revoked any time.
- Internet tunnels are deferred until an app genuinely needs inbound
  traffic (e.g. Jellyfin away from home). When that day comes: tunnel →
  nginx path-allowlist gate → app, so no login page ever faces the
  internet.

## Endpoints

| Service | Where | Port | Serves |
|---|---|---|---|
| Grafana | monitoring host | `:3000` | dashboards; Fleet Status also at the public token URL |
| Prometheus | monitoring host | `:9090` | metric store + query API, 30-day retention |
| Uptime Kuma | monitoring host | `:3001` | up/down checks and notifications |
| node_exporter | every host | `:9100` | host metrics — systemd service, survives Docker outages |
| cAdvisor | every host | `:8080` | per-container metrics |

## Known limits

- **Single point of failure:** Prometheus, Grafana and Uptime Kuma all run
  on one host. Accepted for now — the stack is code, so re-assigning it in
  `host_vars` and re-running `deploy-apps.yml` rebuilds it elsewhere in
  minutes; only TSDB history is lost. The off-fleet dead-man's switch
  (heartbeat role + Healthchecks.io) covers *knowing about* an outage;
  still planned: a duplicate Prometheus on a second host for metrics
  continuity.
- **Private-cloud plane:** when the Incus cluster lands (see
  [../ROADMAP.md](../ROADMAP.md)), its metrics endpoint becomes one more
  scrape job — per-VM metrics with no agents inside guest VMs and no holes
  in the guest-network firewall.
