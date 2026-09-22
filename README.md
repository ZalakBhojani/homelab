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

## Setup

All `ansible-playbook` commands below run from `ansible/`:

```bash
cd ansible
cp inventory.example.ini inventory.ini   # then fill in your hosts
```

`inventory.ini` is gitignored (it holds internal IPs and usernames), as is
`results/`. Playbooks never store secrets — the LUKS passphrase and sudo
password are prompted at runtime.

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
