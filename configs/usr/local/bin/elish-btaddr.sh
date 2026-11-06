#!/bin/sh
# Program the BT BDADDR into the QCA6390.
# The chip registers hci0 with an all-zero address; the kernel marks it
# unconfigured and bluetoothd never sees a controller. Setting the public
# address configures and powers it. Idempotent: exits 0 once configured.
#
# Usage: elish-btaddr.sh [MAC]
#   with MAC  -> write that fixed address (repo: replace with YOUR factory MAC)
#   without   -> read factory address from persist .bt_nv.bin (default)
NV=/mnt/vendor/persist/bluetooth/.bt_nv.bin
BTMGMT=/usr/bin/btmgmt
WANT="$1"

for i in $(seq 1 30); do
    cur=$($BTMGMT --index hci0 info 2>/dev/null | sed -n "s/^ *addr \([0-9A-Fa-f:]*\).*/\1/p")
    [ -n "$cur" ] && [ "$cur" != "00:00:00:00:00:00" ] && exit 0

    mac="$WANT"
    if [ -z "$mac" ]; then
        [ -r "$NV" ] || { sleep 1; continue; }
        mac=$(od -An -tx1 -N6 "$NV" | tr " " ":" | sed "s/^://")
        [ -n "$mac" ] || { sleep 1; continue; }
    fi
    $BTMGMT --index hci0 public-addr "$mac" 2>/dev/null && exit 0
    sleep 1
done
exit 1
