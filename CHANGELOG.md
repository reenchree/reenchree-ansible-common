# Changelog

All notable changes to the reenchree.common collection. One line per
released version; newest release detailed. Consumers pin the matching git tag.

## 1.13.0
- feat(zfs): **rebuild-onto-existing-disks path.** When the pool is not imported but the configured disks carry ZFS labels, the role now runs `zpool import -d /dev/disk/by-id -N <pool>` (`zfs_import_existing`, default `true`), re-probes, and at the end loads file:// keys + `zfs mount -a`. A fresh OS install or a controller swap converges without a manual import; creation stays opt-in and labelled disks are never created over.
- feat(base): **EFI removable-media fallback loader** (`base_efi_removable_fallback`, default `true`): on UEFI hosts with grub, sets the `grub2/force_efi_extra_removable` debconf answer and runs `grub-install --force-extra-removable` once, so a firmware NVRAM reset (dead CMOS cell, ROM defaults) still boots unattended. Lesson from hercules 2026-09-12.
- fix(zfs): the post-import re-check no longer clobbers the pool probe when skipped.

## 1.12.0 — feat(zfs): `zpool create` opt-in via `zfs_allow_pool_create` (non-imported pool fails the run); `zfs_member` label guard; `zpool list`/`zfs list` probes run under `--check`.

## 1.11.1 — fix(zfs): `Create ZFS datasets` no longer prints dataset encryption keys (key-stripped loop copy + `loop_control.label`); purge/rotate older Semaphore logs as policy dictates.

## 1.11.0 — feat(nut_server): null-valued ups.conf extra keys render as bare flags (`ignorelb`); fix(nut_server): ups.conf changes restart the `nut-driver@<ups>` instances (SIGHUP skips `ignorelb`/`override.*`).

## 1.10.0 — feat: net_watchdog role (Wi-Fi/WG self-healing, rdu-nas); fix(zfs): file://-only zfs-load-key helper (blind replicas broke `load-key -a`).

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
