# reenchree-ansible-common

Shared Ansible collection (`reenchree.common`, namespace `reenchree`, name `common`) consumed by every other `*-ansible` repo in the homelab via `requirements.yml`. Not a runnable playbook — only roles, no inventory, no `playbooks/`.

## Distribution

- **Not published to Galaxy.** Consumers pull from `https://github.com/reenchree/reenchree-ansible-common.git` as a `type: git` collection.
- Downstream repos pin an **annotated git tag** (e.g. `version: v1.10.0`) in `requirements.yml`; bumping the version downstream = bump the tag. `galaxy.yml` `version:` is kept in lockstep with the tag. (SHA→tag migration complete: rdu-nas re-pinned to v1.10.0 on 2026-08-09.)
- Collection deps (declared in `galaxy.yml`): `community.general >=7.0.0`, `ansible.posix >=1.5.0`. Downstream repos must also have these installed.

## Roles

| role | purpose | key variables / gotchas |
|---|---|---|
| `base` | Baseline apt packages (smartmontools, lm-sensors, htop, iotop-c, tmux, sudo, openresolv), grants sudo to `ansible_user`, configures `smartd` with NVMe vs spinning thresholds | `base_packages` (extend, don't replace) |
| `zfs` | Enables contrib repo (classic `sources.list` AND deb822 `.sources` via `zfs_deb822_sources_file`), installs `zfsutils-linux`+headers, creates pool with `ashift=12`, applies dataset properties, installs monthly scrub timer, ships a node_exporter textfile collector for ZFS vdev-error/scrub metrics | `zfs_pool_name` (`tank`), `zfs_pool_type` (`raidz2`), `zfs_disks` (`/dev/disk/by-id/...`, required), `zfs_arc_max_gb` (`8`), `zfs_datasets` (list of dicts with `name/quota/compression/recordsize/snapshots`, optional `encryption:` block for per-dataset native crypto), `zfs_pool_encryption` (pool-level crypto, inherited by `zfs receive` datasets), `zfs_health_metrics_enabled` (`true`; installs `jq`+`zfs-health-metrics.sh`+timer emitting `zfs_vdev_*`/`zfs_pool_scan_*` to the textfile dir — closes the per-vdev-error/scrub gap `pdf/zfs_exporter` leaves; needs zfsutils >= 2.3), `zfs_health_metrics_dir` (must match `node_exporter_textfile_directory`). **Crypto can only be set at create — changing it = destroy + recreate.** |
| `sanoid` | Installs sanoid, templates `/etc/sanoid/sanoid.conf` from `zfs_datasets` | Templates: `frequent` (15m/hourly/daily/monthly), `daily`, `receive_only` (`autosnap=no` — use on syncoid destinations so receive lineage isn't broken), `none` (skip) |
| `node_exporter` | Prometheus node_exporter via apt | `node_exporter_listen_address` (`0.0.0.0:9100`), `node_exporter_extra_args` defaults to `--collector.systemd.enable-start-time-metrics` — **required by the `SyncoidStale` alert in sea-k8s-flux**, do not drop; `node_exporter_textfile_directory` (`/var/lib/node_exporter/textfile_collector`, enables the textfile collector; `""` disables) |
| `zfs_exporter` | Installs ZFS exporter from GitHub releases (thin wrapper over `github_release_exporter`) | `zfs_exporter_version` (`2.3.11`), `:9134`. Systemd unit hardened |
| `smartctl_exporter` | SMART exporter from GitHub releases (thin wrapper over `github_release_exporter`) | `smartctl_exporter_version` (`0.14.0`), `:9633`, `smartctl_exporter_smartctl_interval` (`300s`). Systemd unit now hardened (parity with zfs_exporter, restored in 1.8.0) |
| `nut_exporter` | UPS metrics via DRuggeri/nut_exporter, scraping the local `upsd` anonymously (thin wrapper over `github_release_exporter`; first bare-binary-asset consumer) | `nut_exporter_version` (`3.3.0`), `:9199`, metrics on `/ups_metrics`; `nut_exporter_vars_enable` (CSV; includes `battery.runtime`, absent upstream-default); `nut_exporter_arch` auto-maps from `ansible_architecture` |
| `github_release_exporter` | **Internal** parameterized role backing the release-binary exporters: install a Prometheus exporter from a GitHub release asset (tarball or bare binary) + hardened systemd unit. The stderr-capturing version check lives here (once); the probe runs even under `--check` | required from caller: `_org` `_repo` `_version` `_binary` `_unit_name` `_description` `_listen_address`; `_after`/`_extra_args`/`_arch` optional; `_asset` (full asset filename) + `_archive: false` for bare-binary releases. Not called directly |
| `ops` | Host-lifecycle ops (apt upgrade / reboot / shutdown). **No `tasks/main.yml`** — consumed via `include_role` + `tasks_from: apt_upgrade\|reboot\|shutdown` | `ops_apt_reboot_if_required` (`false`), `ops_apt_*` (lock/retry knobs), `ops_reboot_*`, `ops_shutdown_*`. `apt_upgrade` detects reboot-required via stamp file OR newer-kernel-installed |
| `net_watchdog` | Self-healing watchdog for Wi-Fi + WG uplinked hosts (offsite mini-NAS pattern): per-minute layer diagnosis (link/LAN/WAN/tunnel) + escalating remediation ladder (nmcli bounce → NM restart → USB authorized reset → module reload → xhci rebind). **No reboot rung by design**; ISP outages never remediated; USB topology cached-while-healthy (deep rungs run when the iface is gone). Every rung live-validated on rdu-nas 2026-08-09 | required: `net_watchdog_interface`, `net_watchdog_nm_connection`, `net_watchdog_health_targets` (must answer ICMP from the host — WG hub .1 does NOT from rdu-nas); `net_watchdog_dry_run` (**`true`** — arm per-host after soak), `net_watchdog_hardware_watchdog_seconds` (`0`; >0 = RuntimeWatchdogSec drop-in, the role's only reboot path) |
| `nut_server` | NUT (Network UPS Tools) in `netserver` mode: `upsd` on network + local `upsmon` for shutdown. Renders all of `/etc/nut/*.conf` + optional USB udev rule | `nut_server_upses` (list, required `name`+`driver`; extra keys passed verbatim to ups.conf), `nut_server_users` (list, optional `upsmon: primary\|secondary`), `nut_server_upsmon_monitor` (must reference a user in `nut_server_users`), `nut_server_udev_rules` (list of vid/pid; empty = leave existing rule). Credential-touching tasks have `no_log: true` |

The `nut_client` side is **not** in this collection — downstream repos pull `geerlingguy.nut_client` from Galaxy.

## Who consumes what

| repo | roles used |
|---|---|
| `sea-hercules-ansible` | `base`, `zfs`, `sanoid`, `node_exporter`, `smartctl_exporter`, `zfs_exporter`, `ops` |
| `rdu-nas-ansible` | `base`, `zfs`, `sanoid`, `node_exporter`, `smartctl_exporter`, `zfs_exporter`, `net_watchdog` (the first consumer; ARMED 2026-08-09, fault-injection verified). Pinned v1.10.0; ops-wrapper conversion still pending its own lane |
| `sea-pegasus-ansible` | `node_exporter`, `smartctl_exporter`, `zfs_exporter` (no `base`/`zfs`/`sanoid` — pool managed elsewhere) |
| `sea-misc-ansible` | `nut_server`, `nut_exporter` (the only consumer of both), `ops` |
| `sea-k8s-ansible` | **does not consume this collection** — uses `k3s-io/k3s-ansible` directly |

`blr-k8s-ansible` is not checked out locally; assume similar usage if/when it appears.

## Releasing changes

1. Make change, commit, bump `version:` in `galaxy.yml`, update `CHANGELOG.md`, push to `main` on GitHub.
2. Create the annotated tag (`git tag -a vX.Y.Z`) and push it.
3. In each downstream repo, bump the tag in `requirements.yml` to `vX.Y.Z`.
4. Re-run `ansible-galaxy collection install -r requirements.yml --force` in the consumer (Semaphore does this automatically on task runs).

## Layout

```
galaxy.yml
CHANGELOG.md       # one line per released version; detail the current one
README.md          # exhaustive per-role variable docs (keep in sync when adding vars)
.gitignore         # .ansible/ (self-install artifact), *.tar.gz, *.retry
roles/
  base/            defaults handlers tasks
  zfs/             defaults handlers tasks files
  sanoid/          tasks templates                    # no defaults/ — driven by consumer's zfs_datasets
  node_exporter/   defaults handlers tasks
  zfs_exporter/    defaults tasks                     # thin wrapper (no handlers/)
  smartctl_exporter/ defaults tasks                   # thin wrapper (no handlers/)
  nut_exporter/    defaults tasks                     # thin wrapper (no handlers/)
  github_release_exporter/ defaults tasks             # internal, backs the release-binary exporters (no handlers/ since 1.8.1)
  ops/             defaults tasks                      # no tasks/main.yml — tasks_from entrypoints
  nut_server/      defaults handlers tasks templates
  net_watchdog/    defaults files tasks templates      # script is a static file (bash ${#arr[@]} = Jinja comment trap); config via /etc/default env file
```
