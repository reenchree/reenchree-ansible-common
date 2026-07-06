# Changelog

All notable changes to the reenchree.common collection. One line per
released version; 1.8.0 detailed. Consumers pin the matching git tag.

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
