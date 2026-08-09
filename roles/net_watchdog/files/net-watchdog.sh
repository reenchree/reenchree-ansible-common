#!/bin/bash
# net-watchdog: self-heals the Wi-Fi + WireGuard path. Managed by Ansible
# (reenchree.common.net_watchdog) — config in /etc/default/net-watchdog.
#
# Each tick diagnoses which layer is broken (link/LAN/WAN/tunnel) and
# remediates only that layer, escalating through a ladder of resets that were
# each validated live before this role existed. Deliberately has NO reboot
# rung: the systemd hardware watchdog covers kernel hangs, and everything
# softer is reachable from userspace. An ISP outage (LAN up, WAN down) is
# never remediated — nothing local can fix it.
set -u

. /etc/default/net-watchdog

read -ra HEALTH <<< "$HEALTH_TARGETS"
read -ra WAN <<< "$WAN_TARGETS"
WIFI_LADDER=(nmcli_bounce nm_restart usb_reset module_reload xhci_rebind)
WG_LADDER=(wg_restart)
# rungs fire DWELL apart; after this many total actions, slow to RETRY_IVL
FAST_ACTIONS=5

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock -n 9 || exit 0

NOW=$(date +%s)
log() { logger -t net-watchdog "$*"; }

# Topology (USB device, module, xhci PCI address) is derived while the
# interface exists and cached — the deep rungs run exactly when it's gone.
cache_topology() {
    local devpath usb_dev module pci
    devpath=$(readlink -f "/sys/class/net/$IFACE/device" 2>/dev/null) || return 0
    usb_dev=$(basename "$(dirname "$devpath")")
    module=$(basename "$(readlink -f "$devpath/driver/module" 2>/dev/null)")
    pci=$(grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]' <<< "$devpath" | head -1)
    [ -e "/sys/bus/usb/devices/$usb_dev" ] && echo "$usb_dev" > "$STATE_DIR/usb_dev"
    [ -n "$module" ] && [ "$module" != "." ] && echo "$module" > "$STATE_DIR/module"
    [ -n "$pci" ] && echo "$pci" > "$STATE_DIR/pci"
}

bump_counter() {
    local f="$STATE_DIR/counters" n="$1" cur
    touch "$f"
    cur=$(awk -v n="$n" '$1==n{print $2}' "$f")
    if [ -n "$cur" ]; then
        sed -i "s/^$n .*/$n $((cur + 1))/" "$f"
    else
        echo "$n 1" >> "$f"
    fi
}

write_metrics() {
    local healthy="$1" since="$2" idx="$3" diag="$4" tmp
    [ -n "$TEXTFILE_DIR" ] && [ -d "$TEXTFILE_DIR" ] || return 0
    tmp="$TEXTFILE_DIR/net_watchdog.prom.$$"
    {
        echo "net_watchdog_healthy $healthy"
        echo "net_watchdog_last_run_timestamp_seconds $NOW"
        echo "net_watchdog_outage_start_timestamp_seconds $since"
        echo "net_watchdog_action_idx $idx"
        echo "net_watchdog_dry_run $([ "$DRY_RUN" = true ] && echo 1 || echo 0)"
        for l in wifi isp wg; do
            echo "net_watchdog_diag{layer=\"$l\"} $([ "$diag" = "$l" ] && echo 1 || echo 0)"
        done
        if [ -f "$STATE_DIR/counters" ]; then
            echo "# TYPE net_watchdog_actions_total counter"
            while read -r n v; do
                echo "net_watchdog_actions_total{action=\"$n\"} $v"
            done < "$STATE_DIR/counters"
        fi
    } > "$tmp" && mv "$tmp" "$TEXTFILE_DIR/net_watchdog.prom"
}

run_action() {
    local d m p
    case "$1" in
        nmcli_bounce)
            nmcli con down "$NM_CONN" >/dev/null 2>&1
            sleep 5
            nmcli con up "$NM_CONN" >/dev/null 2>&1
            ;;
        nm_restart)
            systemctl restart NetworkManager
            sleep 10
            nmcli con up "$NM_CONN" >/dev/null 2>&1 || true
            ;;
        usb_reset)
            d=$(cat "$STATE_DIR/usb_dev" 2>/dev/null) || return 1
            [ -f "/sys/bus/usb/devices/$d/authorized" ] || return 1
            echo 0 > "/sys/bus/usb/devices/$d/authorized"
            sleep 5
            echo 1 > "/sys/bus/usb/devices/$d/authorized"
            ;;
        module_reload)
            m=$(cat "$STATE_DIR/module" 2>/dev/null) || return 1
            modprobe -r "$m" || return 1
            sleep 5
            modprobe "$m"
            ;;
        xhci_rebind)
            p=$(cat "$STATE_DIR/pci" 2>/dev/null) || return 1
            [ -e "/sys/bus/pci/drivers/xhci_hcd/$p" ] || return 1
            echo "$p" > /sys/bus/pci/drivers/xhci_hcd/unbind
            sleep 5
            echo "$p" > /sys/bus/pci/drivers/xhci_hcd/bind
            ;;
        wg_restart)
            systemctl restart "wg-quick@${WG_IF}"
            ;;
    esac
}

# --- health picture ---
link_ok=false lan_ok=false wan_ok=false tunnel_ok=false
[ "$(cat "/sys/class/net/$IFACE/operstate" 2>/dev/null)" = "up" ] && link_ok=true

GW=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="via"){print $(i+1); exit}}')
[ -n "$GW" ] && ping -n -c1 -W2 "$GW" >/dev/null 2>&1 && lan_ok=true

for t in "${WAN[@]}"; do
    ping -n -c1 -W2 "$t" >/dev/null 2>&1 && { wan_ok=true; break; }
done
for t in "${HEALTH[@]}"; do
    ping -n -c1 -W3 "$t" >/dev/null 2>&1 && { tunnel_ok=true; break; }
done
if ! $tunnel_ok; then
    hs=$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk '{print $2; exit}')
    [ -n "${hs:-}" ] && [ "$hs" -gt 0 ] && [ $((NOW - hs)) -lt "$HS_MAX_AGE" ] && tunnel_ok=true
fi

if $tunnel_ok; then
    cache_topology
    if [ -f "$STATE_DIR/unhealthy_since" ]; then
        dur=$((NOW - $(cat "$STATE_DIR/unhealthy_since")))
        acts=$(cat "$STATE_DIR/action_idx" 2>/dev/null || echo 0)
        log "RECOVERED after ${dur}s ($acts remediation(s) attempted)"
        rm -f "$STATE_DIR/unhealthy_since" "$STATE_DIR/action_idx" "$STATE_DIR/last_action_ts"
    fi
    write_metrics 1 0 0 ""
    exit 0
fi

# --- unhealthy ---
if [ ! -f "$STATE_DIR/unhealthy_since" ]; then
    echo "$NOW" > "$STATE_DIR/unhealthy_since"
    log "unhealthy: tunnel down (link=$link_ok lan=$lan_ok wan=$wan_ok)"
fi
SINCE=$(cat "$STATE_DIR/unhealthy_since")
ELAPSED=$((NOW - SINCE))

if ! $link_ok || ! $lan_ok; then
    DIAG=wifi LADDER=("${WIFI_LADDER[@]}")
elif ! $wan_ok; then
    DIAG=isp LADDER=()
else
    DIAG=wg LADDER=("${WG_LADDER[@]}")
fi

IDX=$(cat "$STATE_DIR/action_idx" 2>/dev/null || echo 0)
LAST=$(cat "$STATE_DIR/last_action_ts" 2>/dev/null || echo 0)

act=""
if [ "$DIAG" != isp ] && [ "$ELAPSED" -ge "$GRACE" ]; then
    if [ "$IDX" -eq 0 ]; then
        act=set
    elif [ "$IDX" -lt "$FAST_ACTIONS" ]; then
        [ $((NOW - LAST)) -ge "$DWELL" ] && act=set
    else
        [ $((NOW - LAST)) -ge "$RETRY_IVL" ] && act=set
    fi
    [ -n "$act" ] && act="${LADDER[$((IDX % ${#LADDER[@]}))]}"
fi

if [ -n "$act" ]; then
    echo $((IDX + 1)) > "$STATE_DIR/action_idx"
    echo "$NOW" > "$STATE_DIR/last_action_ts"
    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN: would run '$act' (diag=$DIAG idx=$IDX elapsed=${ELAPSED}s)"
        bump_counter "dryrun_$act"
    else
        log "remediating: '$act' (diag=$DIAG idx=$IDX elapsed=${ELAPSED}s)"
        if run_action "$act"; then
            log "remediation '$act' completed"
        else
            log "remediation '$act' FAILED (rc=$?)"
        fi
        bump_counter "$act"
    fi
fi

write_metrics 0 "$SINCE" "$IDX" "$DIAG"
