#!/system/bin/sh
# gbos_tbnet (started from gbos.rc at boot_completed when hook.sh loaded thunderbolt_net): gives the Thunderbolt network
# link a fixed address, so adb reaches this laptop over a Thunderbolt/USB4 cable to another computer.
#   other computer:  give its thunderbolt0 10.42.0.1/24 (Linux: nmcli con add type ethernet ifname thunderbolt0
#                    ipv4.method manual ipv4.addresses 10.42.0.1/24), then adb connect 10.42.0.2:<port>
#   <port>:          Wireless debugging's port (Settings > Developer options), or 5555 after `adb tcpip 5555`
# adb still asks to authorise the computer's key; nothing here turns adb on.
# Android's ConnectivityService does not manage thunderbolt* interfaces and Android routes by per-network policy tables,
# not "main", so the address and two rules sending this subnet's traffic to "main" are set here. The link comes and goes
# with the cable, so the script checks every 3 s. $1: this side's address (TB_NET_IP in gbos.cfg, /24).
IP=${1:-10.42.0.2}
NET=${IP%.*}.0/24
log -t gbos "tbnet: waiting for thunderbolt network links, address $IP"
while :; do
  ip rule show | grep -q "to $NET lookup main" || ip rule add to $NET lookup main prio 9000
  ip rule show | grep -q "from $IP lookup main" || ip rule add from $IP lookup main prio 9000
  for i in /sys/class/net/thunderbolt*; do
    [ -e "$i" ] || continue
    n=${i##*/}
    ip -4 addr show dev $n | grep -q "inet $IP/" && continue
    ip link set $n up && ip addr add $IP/24 dev $n && log -t gbos "tbnet: $n up as $IP/24" \
      || log -t gbos "tbnet: configuring $n failed"
  done
  sleep 3
done
