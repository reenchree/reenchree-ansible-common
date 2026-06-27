#!/usr/bin/env bash
# Emit ZFS vdev-error and scrub-health metrics for node_exporter's textfile
# collector. Fills the gap left by pdf/zfs_exporter, which exports only
# zfs_pool_health (pool state) -- NOT per-vdev read/write/checksum error
# counters, nor scrub staleness/errors. Those are exactly the early-warning
# signals for a failing drive in a redundant pool (errors accrue before the
# pool ever leaves ONLINE).
#
# Parses `zpool status -j` (JSON; requires zfsutils >= 2.3) with jq and writes
# an atomically-renamed *.prom file into the textfile collector directory.
# Intended to be run from a systemd timer. Managed by the reenchree.common
# zfs role -- do not edit on the host.
set -euo pipefail

TEXTFILE_DIR="${1:-/var/lib/node_exporter/textfile_collector}"
OUT="${TEXTFILE_DIR}/zfs_health.prom"
TMP="$(mktemp "${OUT}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

JSON="$(zpool status -j 2>/dev/null || true)"
[ -n "$JSON" ] || JSON='{}'

# Emit one metric family for every vdev (root/raidz/leaf-disk) carrying the
# given JSON field. vdev_type distinguishes leaf disks ("disk") from the
# raidz/root aggregates, so alerts can target physical drives.
vdev_family() { # $1=json field  $2=metric name
  printf '%s' "$JSON" | jq -r --arg field "$1" --arg metric "$2" '
    .pools // {} | to_entries[] | .key as $pool | .value as $p
    | [ ($p.vdevs // {}) | .. | objects
        | select(has($field) and has("vdev_type") and has("name")) ][]
    | "\($metric){pool=\"\($pool)\",vdev=\"\(.name)\",vdev_type=\"\(.vdev_type)\"} \((.[$field])|tonumber)"
  '
}

{
  echo '# HELP zfs_vdev_read_errors ZFS vdev read errors (cumulative since import/clear).'
  echo '# TYPE zfs_vdev_read_errors gauge'
  vdev_family read_errors zfs_vdev_read_errors

  echo '# HELP zfs_vdev_write_errors ZFS vdev write errors (cumulative since import/clear).'
  echo '# TYPE zfs_vdev_write_errors gauge'
  vdev_family write_errors zfs_vdev_write_errors

  echo '# HELP zfs_vdev_checksum_errors ZFS vdev checksum errors (cumulative since import/clear).'
  echo '# TYPE zfs_vdev_checksum_errors gauge'
  vdev_family checksum_errors zfs_vdev_checksum_errors

  echo '# HELP zfs_vdev_slow_ios ZFS vdev slow I/O count (cumulative since import/clear).'
  echo '# TYPE zfs_vdev_slow_ios gauge'
  vdev_family slow_ios zfs_vdev_slow_ios

  echo '# HELP zfs_pool_error_count ZFS pool data error count (zpool status error_count).'
  echo '# TYPE zfs_pool_error_count gauge'
  printf '%s' "$JSON" | jq -r '
    .pools // {} | to_entries[]
    | "zfs_pool_error_count{pool=\"\(.key)\"} \(((.value.error_count) // "0")|tonumber)"'

  echo '# HELP zfs_pool_scan_errors Errors found during the last/current scrub or resilver.'
  echo '# TYPE zfs_pool_scan_errors gauge'
  printf '%s' "$JSON" | jq -r '
    .pools // {} | to_entries[] | select(.value.scan_stats != null)
    | "zfs_pool_scan_errors{pool=\"\(.key)\"} \(((.value.scan_stats.errors) // "0")|tonumber)"'

  echo '# HELP zfs_pool_scan_start_timestamp_seconds Start time (unix epoch) of the last/current scrub or resilver.'
  echo '# TYPE zfs_pool_scan_start_timestamp_seconds gauge'
  printf '%s' "$JSON" | jq -r '
    .pools // {} | to_entries[]
    | select((.value.scan_stats.pass_start // null) != null)
    | "zfs_pool_scan_start_timestamp_seconds{pool=\"\(.key)\"} \((.value.scan_stats.pass_start)|tonumber)"'
} > "$TMP"

chmod 0644 "$TMP"
mv -f "$TMP" "$OUT"
trap - EXIT
