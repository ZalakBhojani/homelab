# homelab

Provisioning and apps for a small Ubuntu homelab fleet.

## Layout

```
homelab/
├── ansible/                    # host provisioning & one-shot operations
│   ├── ansible.cfg
│   ├── inventory.example.ini   # copy to inventory.ini (gitignored)
│   ├── tpm-luks-unlock.yml
│   ├── expand-root-lv.yml
│   ├── cpu-burnin.yml
│   ├── deploy-apps.yml         # planned: sync app stacks to hosts, compose up
│   ├── group_vars/             # planned: fleet-wide vars
│   ├── host_vars/              # planned: per-host app assignment
│   ├── roles/                  # planned: docker, node_exporter
│   └── results/                # run outputs (gitignored)
└── apps/                       # planned: one Docker Compose stack per app
    ├── pihole/
    ├── jellyfin/
    └── monitoring/             # Prometheus + Grafana
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
