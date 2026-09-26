# Roadmap: dual setup on one fleet

Goal: run two logically isolated planes across the same 3 machines:

1. **Homelab** — the Docker Compose app stacks in `apps/` (pihole, jellyfin,
   monitoring), running directly on the hosts as already planned.
2. **Private cloud** — KVM virtual machines I can hand out to friends,
   reachable by them but walled off from the homelab and the LAN.

## Direction

Keep the hosts as bare-metal Ubuntu (preserving the TPM/LUKS + Ansible
investment) and add **Incus** clustered across the 3 nodes for the private
cloud, rather than reinstalling with Proxmox. Incus *projects* give the
friend-VM world its own namespace, resource limits, and access boundary.

Isolation comes from three layers:

- **Compute** — friend VMs are hardware-virtualized (KVM); isolation from
  host Docker workloads is free.
- **Network** — guest VMs get their own bridge/VLAN, separate from the LAN
  the homelab services use. nftables on each host: guest subnet → internet
  allowed; guest subnet → LAN / homelab / host management denied. Friend
  access via WireGuard or Tailscale terminating into the guest network only.
  Incus + OVN can make per-project networks span the cluster.
- **Resources** — CPU/memory/disk limits on the Incus project so a runaway
  guest VM can't starve homelab apps. VM storage on its own LV/pool so
  guests can't fill the root filesystem.

## Planned work

- [ ] `incus` Ansible role: install, init, cluster the 3 nodes
- [ ] Network layout: guest subnet/VLAN, bridges, nftables rules as a playbook
- [ ] WireGuard/Tailscale ingress for friends (guest network only)
- [ ] Storage: dedicated LV/pool for VM disks
- [ ] Incus project for guests with resource limits
- [ ] Extend monitoring to the VM plane: Incus metrics endpoint
      (`core.metrics_address` + TLS metrics cert) as a Prometheus scrape
      job — per-VM provider view, no agents in guest VMs, no holes in the
      guest-network firewall. One stack covers both planes (pull model +
      inventory-driven targets).
- [ ] Verify isolation: from inside a guest VM, confirm the LAN and homelab
      services are unreachable

## Open questions

- ~~Proxmox instead of Incus~~ — resolved: Ubuntu + Incus, see
  [DECISION.md](DECISION.md) #1. Revisit only if a friend-facing web UI
  becomes a requirement.
- Once the Incus cluster is up: move the Docker app plane into an Incus
  "apps" container per host? See [DECISION.md](DECISION.md) #2, option D —
  compose packaging and `deploy-apps.yml` stay the same either way.
- Resource headroom: jellyfin transcodes + friend VMs on the same small
  nodes may need capacity planning.
