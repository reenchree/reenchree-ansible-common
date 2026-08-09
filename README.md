# reenchree.common

Shared Ansible collection for common roles used across the reenchree homelab infrastructure.

## Roles

### `reenchree.common.base`

Installs baseline system packages (smartmontools, lm-sensors, htop, iotop-c, tmux, sudo, openresolv), grants sudo to `ansible_user`, and configures `smartd` to monitor all disks with sensible NVMe vs spinning thresholds.

**Default variables:**
- `base_packages`: list of apt packages installed (override to add more)

### `reenchree.common.zfs`

Creates and configures a ZFS pool plus its datasets. Enables the contrib repository, installs `zfsutils-linux` + headers, sets ARC max, creates the pool with `ashift=12`, applies pool/dataset properties (compression, atime, xattr, recordsize, quota), installs a monthly scrub timer, and (optionally) a node_exporter textfile collector for ZFS vdev-error + scrub health metrics.

**Default variables:**
- `zfs_pool_name`: `tank`
- `zfs_pool_type`: `raidz2` (also accepts `mirror`, `stripe`, `raidz`, `raidz3`)
- `zfs_disks`: list of `/dev/disk/by-id/...` paths (required)
- `zfs_arc_max_gb`: `8`
- `zfs_health_metrics_enabled`: `true`. Installs `jq` + `/usr/local/bin/zfs-health-metrics.sh` and a systemd timer that parses `zpool status -j` and writes per-vdev `zfs_vdev_{read,write,checksum}_errors` / `zfs_vdev_slow_ios` plus `zfs_pool_error_count` / `zfs_pool_scan_errors` / `zfs_pool_scan_start_timestamp_seconds` into the node_exporter textfile collector dir (scraped on :9100). Fills the gap left by `pdf/zfs_exporter`, which exports only `zfs_pool_health`. Alert rules live in sea-k8s-flux `custom-alerts.yaml` (`zfs-health` group, `job="bare-metal-node"`). Requires zfsutils >= 2.3 for `zpool status -j`.
- `zfs_health_metrics_dir`: `/var/lib/node_exporter/textfile_collector` (must match `node_exporter_textfile_directory`)
- `zfs_health_metrics_interval`: `5min` (systemd `OnUnitActiveSec`)
- `zfs_deb822_sources_file`: `/etc/apt/sources.list.d/debian.sources`. The role enables the `contrib` component (for `zfs-dkms`/`zfsutils-linux`) in both the classic one-line `/etc/apt/sources.list` and this deb822 `.sources` file, whichever exists. Override if the Debian deb822 entry lives in a differently-named `.sources` file.
- `zfs_datasets`: list of dicts with required keys `{name, quota, compression, recordsize, snapshots}`. Optional key `encryption: {cipher, keyformat, keylocation, key_content}` enables per-dataset ZFS native encryption — the role drops the key at `keylocation` (mode 0400) and creates the dataset with encryption properties. Note: encryption properties can only be set at dataset creation; modifying after creation is a destroy + recreate. The role therefore applies the encryption properties only when the dataset does not exist yet — a pre-existing unencrypted dataset that declares an `encryption:` block is left untouched (migrate it out-of-band via `zfs send | zfs recv` into an encrypted dataset; subsequent runs are then idempotent). The key drop at `keylocation` happens regardless of dataset existence, so the keyfile is in place before any out-of-band migration.
- `zfs_pool_encryption` (optional): `{cipher, keyformat, keylocation, key_content}` block. When set, encryption is applied at the **pool** level (`zpool create -O ...`) so every dataset in the pool inherits it — including datasets later created by `zfs receive` (e.g. via syncoid). Use this when you want the entire pool encrypted with a single key. Pool-level encryption can only be set at pool creation; changing it after the fact requires destroying and recreating the pool.

### `reenchree.common.sanoid`

Installs sanoid and templates `/etc/sanoid/sanoid.conf` based on the `zfs_datasets` list (uses each dataset's `snapshots` key to pick a template). Built-in templates (assignable via the dataset's `snapshots:` key):
- `frequent` — 15-min snapshots (8 retained), hourly (48), daily (30), monthly (12)
- `daily` — daily (30), monthly (6)
- `receive_only` — daily (30), monthly (6), but `autosnap=no` so the local sanoid does not create snapshots. Use on the destination side of a syncoid replication so the receive lineage stays intact.
- `none` — dataset is omitted from sanoid.conf (no snapshots managed)

### `reenchree.common.node_exporter`

Installs and configures Prometheus node_exporter via apt.

**Default variables:**
- `node_exporter_listen_address`: `0.0.0.0:9100`
- `node_exporter_extra_args`: `--collector.systemd.enable-start-time-metrics` (enables `node_systemd_unit_start_time_seconds`; required by the `SyncoidStale` alert in sea-k8s-flux)
- `node_exporter_textfile_directory`: `/var/lib/node_exporter/textfile_collector` — when set (the default), the role creates the dir and appends `--collector.textfile.directory` so other roles (e.g. `zfs`) can drop `*.prom` files that get scraped on :9100. Set to `""` to disable.

### `reenchree.common.zfs_exporter`

Downloads, installs, and configures the ZFS exporter from GitHub releases. Thin wrapper over the internal `github_release_exporter` role; the systemd unit is hardened (`ProtectSystem=full`, `ProtectHome=true`, `NoNewPrivileges=true`).

**Default variables:**
- `zfs_exporter_version`: `2.3.11`
- `zfs_exporter_listen_address`: `0.0.0.0:9134`
- `zfs_exporter_extra_args`: extra CLI flags (e.g. `--collector.dataset-snapshot`)

### `reenchree.common.smartctl_exporter`

Downloads and configures the SMART exporter for Prometheus. Thin wrapper over the internal `github_release_exporter` role; the systemd unit is hardened (`ProtectSystem=full`, `ProtectHome=true`, `NoNewPrivileges=true`).

**Default variables:**
- `smartctl_exporter_version`: `0.14.0`
- `smartctl_exporter_listen_address`: `0.0.0.0:9633`
- `smartctl_exporter_smartctl_interval`: `300s`

### `reenchree.common.nut_exporter`

Downloads, installs, and configures [DRuggeri/nut_exporter](https://github.com/DRuggeri/nut_exporter) — Prometheus metrics for a NUT (Network UPS Tools) UPS, scraped from the local `upsd`. Thin wrapper over the internal `github_release_exporter` role; the systemd unit is hardened (`ProtectSystem=full`, `ProtectHome=true`, `NoNewPrivileges=true`). UPS metrics are served on `/ups_metrics` (`/metrics` is the exporter's own process metrics). Connects anonymously to `127.0.0.1:3493` by design — no NUT credentials involved. With a single UPS defined the exporter auto-selects it; multi-UPS hosts need the `?ups=` scrape parameter.

**Default variables:**
- `nut_exporter_version`: `3.3.0`
- `nut_exporter_listen_address`: `0.0.0.0:9199`
- `nut_exporter_vars_enable`: CSV of UPS variables exported as metrics (includes `battery.runtime`, which upstream's default list omits)
- `nut_exporter_arch`: release-asset arch token, auto-mapped from `ansible_architecture` (`x86_64` → `linux-amd64`, `aarch64` → `linux-arm64`)

> `github_release_exporter` is an internal, parameterized role (org/repo/version/binary/unit/description/after/listen/extra_args/asset/archive) that installs a Prometheus exporter from a GitHub release asset — a `.tar.gz` by default, or a bare binary when the caller sets `github_release_exporter_asset` (full asset filename) and `github_release_exporter_archive: false`. It is not called directly — use the `zfs_exporter` / `smartctl_exporter` / `nut_exporter` wrappers.

### `reenchree.common.nut_server`

Installs and configures NUT (Network UPS Tools) in `netserver` mode — `upsd` listening on the network plus a local `upsmon` for shutdown handling. Renders all of `/etc/nut/{nut,ups,upsd,upsd.users,upsmon}.conf` from templates and (optionally) a USB udev rule.

**Default variables:**
- `nut_server_mode`: `netserver`
- `nut_server_listen_address`: `0.0.0.0`, `nut_server_listen_port`: `3493`
- `nut_server_maxretry`: `3`
- `nut_server_upses`: list of UPS dicts. Required keys: `name`, `driver`. Common optional keys: `port`, `vendorid`, `productid`, `serial`, `description`, `pollinterval`. Any other key is rendered verbatim as `key = value` for driver-specific options.
- `nut_server_users`: list of user dicts. Required keys: `name`, `password`. Optional: `actions` (list), `instcmds` (list), `upsmon` (`primary` | `secondary`).
- `nut_server_upsmon_*`: timing knobs (POLLFREQ, HOSTSYNC, DEADTIME, etc.) and `nut_server_upsmon_monitor` (`ups`, `powervalue`, `user`, `password`, `type`) for the local MONITOR line. The MONITOR identity must correspond to one of the entries in `nut_server_users`.
- `nut_server_udev_rules`: list of `{vendorid, productid, comment?}`. Empty (default) means the role does not write `/etc/udev/rules.d/99-nut-ups.rules` and any existing rule is left in place.

Tasks that touch `upsd.users` and `upsmon.conf` set `no_log: true` to keep credentials out of run logs.

### `reenchree.common.ops`

Common host-lifecycle operations (apt upgrade, reboot, shutdown). This role has **no `tasks/main.yml`** — it is consumed via `include_role` with `tasks_from`, not `roles:`:

```yaml
- name: APT upgrade
  ansible.builtin.include_role:
    name: reenchree.common.ops
    tasks_from: apt_upgrade      # or reboot / shutdown
  vars:
    ops_apt_reboot_if_required: false
```

Entrypoints:
- `apt_upgrade` — `apt update` (with lock/retry hardening) + `dist`-upgrade + `autoremove`, then reboot-required detection (the `/run/reboot-required` stamp file OR a newer kernel installed than the running one). Reboots only when `ops_apt_reboot_if_required` is true.
- `reboot` — `ansible.builtin.reboot`.
- `shutdown` — `community.general.shutdown`.

**Default variables:**
- `ops_apt_reboot_if_required`: `false` — opt-in auto-reboot after upgrade.
- `ops_apt_upgrade`: `dist`; `ops_apt_autoremove`: `true`.
- `ops_apt_cache_valid_time`: `3600`.
- `ops_apt_update_cache_retries`: `5`; `ops_apt_update_cache_retry_max_delay`: `60`; `ops_apt_lock_timeout`: `300` — apt-lock/retry tolerance for flaky or contended hosts.
- `ops_reboot_msg`: `Reboot initiated by Ansible`; `ops_reboot_timeout`: `600`; `ops_reboot_post_reboot_delay`: `10` (post-upgrade reboot only).
- `ops_shutdown_delay`: `60`; `ops_shutdown_msg`: `Shutdown initiated by Ansible`.

### `reenchree.common.net_watchdog`

Self-healing watchdog for hosts whose only uplink is Wi-Fi + WireGuard (the offsite mini-NAS pattern). A per-minute timer diagnoses which layer is broken — link, LAN, WAN, or tunnel — and remediates only that layer, escalating through a ladder of progressively deeper resets: `nmcli` bounce → NetworkManager restart → USB device reset (`authorized` toggle) → driver module reload → xhci controller rebind. There is deliberately **no reboot rung**; kernel/PID1 hangs are covered by the optional hardware watchdog. An ISP outage (LAN up, WAN down) is never remediated. USB topology (device path, module name, xhci PCI address) is derived at runtime while healthy and cached, since the deep rungs run exactly when the interface has vanished. Emits `net_watchdog_*` metrics via the node_exporter textfile collector.

**Default variables:**
- `net_watchdog_interface`: `""` — **required**, the Wi-Fi interface (e.g. `wlx6c1ff7857a30`).
- `net_watchdog_nm_connection`: `""` — **required**, the NetworkManager profile name.
- `net_watchdog_health_targets`: `[]` — **required**, IPs proving the tunnel end-to-end (must answer ICMP from this host — the WG hub IP may not!).
- `net_watchdog_wg_interface`: `wg0`; `net_watchdog_wan_targets`: `[1.1.1.1, 8.8.8.8]`.
- `net_watchdog_handshake_max_age_seconds`: `180` — a fresh WG handshake also counts as tunnel-healthy (protects against the health-target host itself being down).
- `net_watchdog_dry_run`: `true` — **safe-by-default**: logs and metrics only; set `false` per-host to arm after a soak.
- `net_watchdog_grace_seconds`: `600` — no action until an outage lasts this long (residential-ISP flap budget).
- `net_watchdog_rung_dwell_seconds`: `300`; `net_watchdog_retry_interval_seconds`: `3600` — after 5 actions the ladder cycles at the slower retry cadence, forever (no give-up state).
- `net_watchdog_interval_seconds`: `60`; `net_watchdog_boot_delay_seconds`: `180`.
- `net_watchdog_state_dir`: `/var/lib/net-watchdog`; `net_watchdog_textfile_directory`: `/var/lib/node_exporter/textfile_collector` (`""` disables metrics).
- `net_watchdog_hardware_watchdog_seconds`: `0` — `> 0` arms the systemd hardware watchdog (`RuntimeWatchdogSec` drop-in + daemon-reexec); the only reboot path this role configures.

## Installation

Add to your `requirements.yml`:

```yaml
collections:
  - name: https://github.com/reenchree/reenchree-ansible-common.git
    type: git
    version: main
```

Then install:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Usage

```yaml
roles:
  - role: reenchree.common.base
  - role: reenchree.common.zfs
  - role: reenchree.common.sanoid
  - role: reenchree.common.node_exporter
  - role: reenchree.common.zfs_exporter
  - role: reenchree.common.smartctl_exporter
  - role: reenchree.common.nut_server
  - role: reenchree.common.nut_exporter
```
