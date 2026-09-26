# apps

One folder per application, each a self-contained Docker Compose stack:

```
apps/<name>/
├── compose.yml
├── .env.example      # real .env is gitignored but deployed if present
├── *.j2              # optional — rendered against the Ansible inventory
│                     # at deploy time (targets, host lists, …)
└── <config files the container mounts>
```

Deployment is `ansible/deploy-apps.yml`; which host runs which app is the
`apps:` list in `ansible/host_vars/` (see `host_vars.example/`).

## monitoring

Prometheus (:9090), Grafana (:3000), Uptime Kuma (:3001). Runs on one host.

- `prometheus.yml.j2` — scrape targets generated from the inventory: every
  `[homelab]` host's node_exporter (:9100) and cadvisor (:8080). Adding a
  host to the inventory adds it to monitoring on the next deploy.
- Grafana auto-provisions the Prometheus datasource; set the admin password
  in `.env` (copy `.env.example`). For dashboards, import IDs **1860**
  (Node Exporter Full) and **14282** (cAdvisor) as a starting point.
- Uptime Kuma keeps its checks in its own volume — configure via its UI.

## cadvisor

Per-container metrics, one instance on **every** host (each only sees its
own host's containers). Scraped by the monitoring stack's Prometheus.

## Planned

`pihole/` (×2 hosts), a reverse proxy (Caddy or Traefik), `jellyfin/` — see
[../ROADMAP.md](../ROADMAP.md).
