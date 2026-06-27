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

Downloads, installs, and configures the ZFS exporter from GitHub releases.

**Default variables:**
- `zfs_exporter_version`: `2.3.11`
- `zfs_exporter_listen_address`: `0.0.0.0:9134`
- `zfs_exporter_extra_args`: extra CLI flags (e.g. `--collector.dataset-snapshot`)

### `reenchree.common.smartctl_exporter`

Downloads and configures the SMART exporter for Prometheus.

**Default variables:**
- `smartctl_exporter_version`: `0.14.0`
- `smartctl_exporter_listen_address`: `0.0.0.0:9633`
- `smartctl_exporter_smartctl_interval`: `300s`

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
```
