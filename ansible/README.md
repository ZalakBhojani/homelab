# ansible

Host provisioning and one-shot operations for the fleet. All commands below
run from this directory.

## Setup

```bash
cp inventory.example.ini inventory.ini   # then fill in your hosts
cp -r host_vars.example host_vars        # rename files to your hostnames,
                                         # edit each host's app list
```

`inventory.ini` and `host_vars/` are gitignored (they hold internal IPs and
usernames), as is `results/`. Playbooks never store secrets — the LUKS
passphrase is prompted at runtime, and the sudo password comes from the
macOS Keychain via `become-pass.sh` (an executable `become_password_file`;
Ansible uses its stdout). One-time setup on the controller:

```bash
security add-generic-password -s homelab-become -a zalak -w
```

No NOPASSWD anywhere — the hosts still require the sudo password; it's
just supplied from the Keychain instead of typed per run. Passing `-K`
still overrides it when you want an interactive prompt.

## provision.yml

Baseline for every host: Docker + Compose (app runtime) and
`prometheus-node-exporter` as a native systemd service on :9100 — native,
not a container, so host metrics keep flowing even when Docker is down.
Idempotent; run it whenever a new host joins the fleet.

```bash
ansible-playbook provision.yml -K
```

## deploy-apps.yml

Deploys the compose stacks in `../apps/` to their assigned hosts. Assignment
is the `apps:` list in `host_vars/<host>.yml`. Per app it syncs the folder
to `/opt/apps/<name>/` (a local `.env` next to the compose file rides
along), renders any top-level `*.j2` against the inventory (e.g. Prometheus
scrape targets are generated from the `[homelab]` group), then
`docker compose up -d`.

```bash
ansible-playbook deploy-apps.yml -K
ansible-playbook deploy-apps.yml -K --limit 192.168.1.10   # one host
```

Re-running is safe: compose only restarts services whose config changed.

## tpm-luks-unlock.yml

Enrolls the TPM2 into the LUKS2 root volume so the servers boot
without a passphrase prompt. Idempotent — safe to re-run.

What it does per host (one host at a time, `serial: 1`):

1. Reads the root entry from `/etc/crypttab` and resolves the LUKS device.
2. `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7` (skipped if a
   TPM2 token is already enrolled). The passphrase keyslot is kept as fallback.
3. Adds `tpm2-device=auto` to the crypttab options (backs up the file).
4. Drops `/etc/dracut.conf.d/tpm2.conf` and rebuilds the initramfs.

### Run

```bash
ansible-playbook tpm-luks-unlock.yml -K
```

`-K` asks for your sudo password; it then prompts for the existing LUKS
passphrase (hidden, not logged). To also reboot each host and verify:

```bash
ansible-playbook tpm-luks-unlock.yml -K -e reboot_after=true
```

The passphrase is prompted once per run — if the hosts ever have different
LUKS passphrases, run per host with `--limit 10.0.0.10` etc.

### After a firmware update / Secure Boot change

PCR 7 changes, so boot falls back to the passphrase prompt. Re-enroll with:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3
```

(or just delete the token and re-run the playbook).

## expand-root-lv.yml

Grows `ubuntu-lv` (root) inside the LUKS-backed `ubuntu-vg` — online, no
reboot, and no effect on TPM unlocking (LVM sits above LUKS). Never shrinks
(`shrink: false`).

How much to grow is `lv_size`, passed straight to LVM:

- `+50%FREE` — add half of the VG's remaining free space (default)
- `80%VG` — grow to 80% of the whole VG; absolute target, idempotent
- `+50G` — add 50 GiB

### Run

```bash
ansible-playbook expand-root-lv.yml -K                      # default +50%FREE
ansible-playbook expand-root-lv.yml -K -e lv_size=80%VG
ansible-playbook expand-root-lv.yml -K -e lv_size=+25%FREE --limit 10.0.0.10
```

Note: `+X%FREE` grows on *every* run (X% of whatever is free at that moment),
so re-running keeps nibbling at the free space. Use the `%VG` form when you
want a fixed target that is safe to re-run.

## cpu-burnin.yml

Parallel CPU burn-in for refurbished/new machines: saturates every core with
`stress-ng --cpu-method all --verify` while sampling `sensors` every 2s, then
collects logs and fails the play if a CPU computed a wrong result under load.
Runs on all hosts concurrently; the load and sampler run detached on each
host (Ansible async), so an SSH drop mid-soak can't lose the metrics.

What it does per host:

1. Installs `stress-ng` + `lm-sensors`; loads `dell_smm_hwmon` (fan RPM
   visibility) on Dell hardware — these are the only steps needing sudo,
   tagged `setup`.
2. Records an idle `sensors` baseline and the core throttle counter.
3. Starts a background temperature sampler (2s interval, self-terminating).
4. Runs `stress-ng --cpu <ncores> --cpu-method all --verify --timeout Nm
   --metrics-brief` (~90 algorithms rotating across ALU/FPU/SIMD, every
   result checked against known-good values).
5. Fetches logs to `results/<timestamp>/<host>/{stress,sensors,baseline}.log`
   and prints a summary: bogo ops/s, peak core temp, throttle-event delta.

Pass = `failed: 0`, `metrics untrustworthy: 0`, 0 new throttle events, and
steady-state temps that plateau (creeping temps on a long soak = paste/
heatsink problem). Bogo ops are only comparable between hosts on the same
stress-ng version — never against numbers from elsewhere.

### Run

```bash
# first run on a new server (installs packages; add the host to [homelab] first)
ansible-playbook cpu-burnin.yml -K --limit 10.0.0.13

# whole fleet, already provisioned — no sudo needed
ansible-playbook cpu-burnin.yml --skip-tags setup

# longer soak (better test of thermal paste / sustained cooling)
ansible-playbook cpu-burnin.yml --skip-tags setup -e burnin_minutes=30
```
