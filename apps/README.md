# apps

One folder per application, each a self-contained Docker Compose stack:

```
apps/<name>/
├── compose.yml
├── .env.example      # real .env is gitignored
└── <config files the container mounts>
```

Planned: `pihole/`, `jellyfin/`, `monitoring/` (Prometheus + Grafana).
Deployment will be `ansible/deploy-apps.yml`: sync the app folder to its
assigned host, then `docker compose up -d`. Nothing here yet — being built.
