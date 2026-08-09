# Changelog

All notable changes to the reenchree.common collection. One line per
released version; newest release detailed. Consumers pin the matching git tag.

## 1.10.0
- feat(net_watchdog): new role — self-healing watchdog for Wi-Fi + WireGuard uplinked hosts (offsite mini-NAS pattern). Layer-diagnosing (link/LAN/WAN/tunnel), escalating remediation ladder (nmcli bounce → NM restart → USB `authorized` reset → module reload → xhci rebind), each rung validated live on rdu-nas before the role was written. No reboot rung by design; optional systemd hardware-watchdog arming (`net_watchdog_hardware_watchdog_seconds`) covers kernel hangs. Dry-run-by-default; `net_watchdog_*` textfile metrics. Born from the 2026-07-11→08-09 rdu-nas outage (AP dropped the client; box sat healthy but offline for 4 weeks with no self-recovery).
- fix(zfs): zfs-load-key.service now runs a file://-only helper (`zfs-load-file-keys.sh`) instead of `zfs load-key -a` — `-a` exits 255 on datasets whose keys are absent by design (raw-received blind replicas, e.g. rdu-nas `tank/storage`), leaving a red FAILED unit every boot. Genuine file:// load failures still fail the unit. No behavior change on hosts where all keylocations are file:// (Hercules).

## 1.9.0
- feat(nut_exporter): new thin-wrapper role installing DRuggeri/nut_exporter (UPS metrics from a local upsd on :9199, `/ups_metrics`). Anonymous by design — no NUT credentials in units or logs. Arch auto-mapped from `ansible_architecture` (amd64/arm64).
- feat(github_release_exporter): support bare-binary release assets via `github_release_exporter_asset` (full asset filename, default = classic tarball shape) + `github_release_exporter_archive` (false = skip unarchive). Defaults reproduce prior behavior exactly; zfs/smartctl callers verified byte-identical in check mode.
- fix(github_release_exporter): version probe now runs under `--check` (`check_mode: false`) — previously a skipped probe registered `stdout=""`, forcing a bogus reinstall decision that made every check-mode run fail at the extract step.

## 1.8.1 — fix(github_release_exporter): in-role registered restarts instead of a shared handler (dedupe broke dual-exporter bumps).

## 1.8.0
- refactor(exporters): `zfs_exporter` and `smartctl_exporter` now delegate to a shared internal `github_release_exporter` role; public var names/defaults unchanged.
- fix(smartctl_exporter): systemd unit gains `ProtectSystem=full` / `ProtectHome=true` / `NoNewPrivileges=true` (restores parity with `zfs_exporter`).
- fix(zfs): contrib enablement now also handles Debian 12+/trixie deb822 `.sources` files (previously silently no-op'd); idempotent for classic and deb822.
- feat(ops): new `ops` role with `tasks_from` entrypoints `apt_upgrade` / `reboot` / `shutdown` (`ops_*` vars; opt-in auto-reboot via `ops_apt_reboot_if_required`).
- chore: add `.gitignore`; drop the untracked self-install artifact.

## 1.7.0 — feat(zfs): vdev-error + scrub health metrics via node_exporter textfile collector; boot-time encryption-key load fix; base sysstat.
## 1.6.0 — feat: reusable `nut_server` (NUT UPS) role.
## 1.5.0 — feat(zfs): pool-level native encryption.
## 1.4.0 — feat(zfs): per-dataset native encryption.
## 1.3.1 — chore: README + comments cleanup.
## 1.3.0 — feat(node_exporter): `extra_args`, default enable-start-time-metrics.
## 1.2.2 — fix(zfs): validate disk count against `pool_type`.
## 1.2.1 — fix(smartctl_exporter): capture stderr in version check.
## 1.2.0 — feat(sanoid): `receive_only` template for syncoid destinations.
## 1.1.0 — feat: promote `base`, `zfs`, `sanoid` roles from sea-hercules-ansible.
## 1.0.0 — initial collection (`node_exporter`, `zfs_exporter`).
