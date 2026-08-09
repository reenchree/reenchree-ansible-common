#!/bin/sh
# Load ZFS keys for file:// keylocations only. Datasets whose keys are
# absent by design (raw-received blind replicas, keylocation=prompt) are
# skipped so boot stays clean; a genuine file:// load failure still fails
# the unit. Managed by Ansible (reenchree.common.zfs).
set -eu
zfs list -H -o name,keylocation,keystatus -t filesystem |
while IFS="	" read -r name keyloc keystatus; do
    case "$keyloc" in
        file://*) ;;
        *) continue ;;
    esac
    [ "$keystatus" = "unavailable" ] || continue
    zfs load-key "$name"
done
