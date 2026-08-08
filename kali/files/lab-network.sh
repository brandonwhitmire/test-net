#!/bin/bash
# Configure eth1 (pentest-lab, 10.0.0.50/24) — and ONLY eth1.
#
# eth0 (vagrant-libvirt management DHCP) is deliberately not touched here:
# this script runs over SSH *through* eth0, so it cannot bootstrap it, and
# restarting the network stack would kill the connection Vagrant is using.
# Management DHCP has to come from the box image itself — see kali/README.md.
set -euo pipefail

LAB_IP="${LAB_IP:-10.0.0.50}"
LAB_CIDR="${LAB_CIDR:-24}"

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -n "$0" "$@"
fi

# Live now.
ip link set eth1 up
ip addr replace "${LAB_IP}/${LAB_CIDR}" dev eth1

# Persist for next boot. No service restarts — the config is picked up then.
if [[ -d /etc/NetworkManager/system-connections ]] && systemctl is-active --quiet NetworkManager; then
  conn=/etc/NetworkManager/system-connections/lab-eth1.nmconnection
  umask 077
  cat >"$conn" <<EOF
[connection]
id=lab-eth1
uuid=aaaaaaaa-bbbb-cccc-dddd-000000000002
type=ethernet
interface-name=eth1
autoconnect=true

[ipv4]
method=manual
addresses=${LAB_IP}/${LAB_CIDR}
never-default=true

[ipv6]
method=ignore
EOF
  chmod 600 "$conn"
elif ! grep -q '^interface eth1$' /etc/dhcpcd.conf 2>/dev/null; then
  # nogateway: the lab NAT must not steal the default route from eth0.
  cat >>/etc/dhcpcd.conf <<EOF

# lab: pentest-lab static (added by kali/files/lab-network.sh)
interface eth1
static ip_address=${LAB_IP}/${LAB_CIDR}
nogateway
EOF
fi

ip -br a
