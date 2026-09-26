# homelab

Provisioning and apps for a small Ubuntu homelab fleet.

## Layout

```
homelab/
├── ansible/                    # host provisioning & one-shot operations
│   ├── ansible.cfg
│   ├── inventory.example.ini   # copy to inventory.ini (gitignored)
│   ├── provision.yml           # baseline: docker + node_exporter roles
│   ├── deploy-apps.yml         # sync app stacks to hosts, compose up
│   ├── tpm-luks-unlock.yml
│   ├── expand-root-lv.yml
│   ├── cpu-burnin.yml
│   ├── host_vars.example/      # copy to host_vars/ (gitignored): per-host apps
│   ├── roles/                  # docker, node_exporter
│   └── results/                # run outputs (gitignored)
└── apps/                       # one Docker Compose stack per app
    ├── monitoring/             # Prometheus + Grafana + Uptime Kuma
    ├── cadvisor/               # container metrics, every host
    ├── pihole/                 # planned
    └── jellyfin/               # planned
```

The split: `ansible/` describes the *hosts* (disks, TPM, Docker, exporters);
`apps/` describes the *applications* as self-contained compose stacks with
their config and a committed `.env.example` (real `.env` gitignored). An
Ansible playbook is the deployment glue — which app runs on which host is
data in `host_vars/`, not folder structure.

## Getting started

- **[ansible/](ansible/README.md)** — inventory setup and docs for each
  playbook (TPM LUKS unlock, root LV expansion, CPU burn-in).
- **[apps/](apps/README.md)** — the per-app compose convention; stacks are
  being built.
- **[ROADMAP.md](ROADMAP.md)** — the dual-setup goal: homelab apps plus an
  isolated private cloud (friend VMs) on the same 3 machines.
- **[DECISION.md](DECISION.md)** — decision records (why Ubuntu + Incus
  over Proxmox).
