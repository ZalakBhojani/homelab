# Decisions

Decision records for choices that shape the fleet. Newest first.

## 2. Homelab app runtime: Docker Compose; daemon on the host for now

**Date:** 2026-09-26 · **Status:** accepted (daemon placement deliberately
revisitable)

### Context

Challenge to decision #1's assumption: since Incus is coming anyway, why
run homelab apps as Docker Compose on the hosts instead of under Incus?
Incus *can* run them — the question is in what shape and at what cost.

### Options considered

**A. Compose stacks, Docker on the host (chosen for now)** — the current
`apps/` + `deploy-apps.yml` model.

**B. Incus system containers, apps installed natively (no Docker)** —
rejected: the self-hosted ecosystem ships maintained OCI images and
compose examples for everything (pihole, Jellyfin, Grafana, …). Going
native makes us the package integrator: version pinning, upgrades,
systemd units, no community docs apply. Permanent tax on every new app.

**C. Incus OCI mode (`incus launch docker:…`)** — rejected: runs single
containers, no Compose semantics. A stack like monitoring (3 services,
volumes, inter-service DNS, `.env`) would be hand-wired per container
with profiles and proxy devices. Compose *is* the multi-service app
format; Incus has no equivalent.

**D. Compose stacks, Docker nested in an Incus "apps" container per
host** — deferred, not rejected. Buys: host becomes a pure Incus
appliance; Docker's iptables never touch the host that enforces the
guest-plane nftables (kills the known Docker/Incus firewall clash at the
root); apps container gets its own stable LAN IP; Incus snapshots =
rollback of the whole app environment before upgrades. Costs: one more
OS layer to patch per host, `security.nesting` quirks, and Jellyfin's
iGPU + media disks cross two boundaries (host → Incus device → Docker
device).

### Decision

Split it. **Packaging: Docker Compose — locked** (B and C trade the
ecosystem for tidiness). **Daemon placement: on the host today; revisit
option D once the Incus cluster exists.** This is not a one-way door:
`deploy-apps.yml` syncs a folder and runs `docker compose up` — it does
not care whether the inventory target is a bare host or an Incus
container running Docker. Migrating to D later is: launch an apps
container per host, repoint the inventory, redeploy. `apps/` never
changes.

## 1. Virtualization layer: Ubuntu + Incus, not Proxmox

**Date:** 2026-09-26 · **Status:** accepted

### Context

The fleet has one goal with two planes (see [ROADMAP.md](ROADMAP.md)):
homelab app stacks (Docker Compose) and a private cloud of friend-accessible
VMs, logically isolated, on the same 3 machines. Both need a virtualization
layer for the VM side. The hosts are already bare-metal Ubuntu with
TPM/LUKS unlock and Ansible provisioning.

### Options considered

**A. Ubuntu Server + Incus (chosen)** — keep the existing OS; Docker and
Incus run side by side as packages. Homelab apps stay on bare metal; Incus
manages KVM VMs (grouped in an Incus *project*) for the private cloud.

- One OS per machine; no reinstall — TPM/LUKS, LV layout, and the Ansible
  inventory keep working as-is.
- Apps on bare metal: no virtualization overhead, Jellyfin gets the iGPU
  for transcoding directly.
- Clean CLI/API → automatable with the same Ansible style as the rest of
  the repo. Fully open source.
- Weaker web UI than Proxmox; guest networking, firewall, and backups are
  DIY. Known gotcha: Docker's iptables rules can block Incus bridge
  traffic (documented, standard fix).

**B. Proxmox VE** — wipe the machines and install Proxmox, a Debian-based
hypervisor OS. Homelab apps would move into an Ubuntu VM (or Docker-in-LXC)
per node.

- Turnkey web UI, clustering, live migration, backups (PBS), per-user
  permissions — best if friends should self-service VMs in a browser.
- Costs a full reinstall; the installer doesn't do LUKS out of the box, so
  the TPM/LUKS setup becomes a manual Debian project.
- Two OS layers to patch per node (Proxmox host + Ubuntu guest), since the
  Proxmox host is meant to stay a thin appliance.
- Jellyfin transcoding needs GPU passthrough (locks the GPU to one VM) or
  LXC device mapping. Automation moves to the Proxmox API/Terraform —
  the existing Ansible stops being the whole story.

### Decision

Option A: Ubuntu Server + Incus. The existing bare-metal investment
(TPM/LUKS, Ansible, one OS to maintain) outweighs Proxmox's turnkey UI,
and friends need *access to* VMs — via WireGuard/Tailscale into an
isolated guest network — not a self-service portal. Revisit only if a
friend-facing management UI becomes a requirement.
