#!/usr/bin/env bash
# Unstick `vagrant up kali` hung on "Waiting for domain to get an IP address...".
#
# Vagrant-libvirt only proceeds once eth0 (management / vagrant-libvirt NAT)
# gets a DHCP lease. The Packer box may not autoconnect that NIC until SSH —
# chicken-and-egg. This seeds DHCP via the guest virtual console (TTY3).
#
# Usage (second terminal while `vagrant up kali` is waiting):
#   ./kali/seed-mgmt-dhcp.sh
#
# Or in the Kali GUI/SPICE terminal:
#   sudo nmcli device connect eth0 || sudo dhclient -v eth0
set -euo pipefail

DOMAIN="${DOMAIN:-test-net_kali}"

python3 - <<'PY'
import subprocess, time, sys

domain = "test-net_kali"

def send(*keys):
    subprocess.check_call(
        ["virsh", "-c", "qemu:///system", "send-key", domain, *keys],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.06)

def text(s):
    special = {
        " ": "KEY_SPACE",
        "-": "KEY_MINUS",
        ".": "KEY_DOT",
        "/": "KEY_SLASH",
        "=": "KEY_EQUAL",
        ";": "KEY_SEMICOLON",
        "'": "KEY_APOSTROPHE",
        '"': ("KEY_LEFTSHIFT", "KEY_APOSTROPHE"),
        ":": ("KEY_LEFTSHIFT", "KEY_SEMICOLON"),
        "_": ("KEY_LEFTSHIFT", "KEY_MINUS"),
        "|": ("KEY_LEFTSHIFT", "KEY_BACKSLASH"),
        "\\": "KEY_BACKSLASH",
        "$": ("KEY_LEFTSHIFT", "KEY_4"),
        "(": ("KEY_LEFTSHIFT", "KEY_9"),
        ")": ("KEY_LEFTSHIFT", "KEY_0"),
        "!": ("KEY_LEFTSHIFT", "KEY_1"),
        "`": "KEY_GRAVE",
    }
    for ch in s:
        if ch.isalpha():
            send(f"KEY_{ch.upper()}")
        elif ch.isdigit():
            send(f"KEY_{ch}")
        elif ch in special:
            v = special[ch]
            send(*v) if isinstance(v, tuple) else send(v)
        else:
            raise SystemExit(f"unsupported char: {ch!r}")

for _ in range(90):
    st = subprocess.check_output(
        ["virsh", "-c", "qemu:///system", "domstate", domain], text=True
    ).strip().lower()
    if "running" in st or "ejecutando" in st:
        break
    time.sleep(2)
else:
    sys.exit("domain not running")

# Prefer text TTY over GDM (more reliable for send-key).
time.sleep(3)
send("KEY_LEFTCTRL", "KEY_LEFTALT", "KEY_F3")
time.sleep(2)

text("vagrant")
send("KEY_ENTER")
time.sleep(1.2)
text("vagrant")
send("KEY_ENTER")
time.sleep(2)

# DHCP on first non-loopback iface (eth0 or enpXs0 / ens3).
cmds = [
    "sudo -n true",
    "IFACE=$(ip -o link show | awk -F': ' '$2!=\"lo\"{print $2; exit}'); echo IFACE=$IFACE; sudo nmcli device connect \"$IFACE\" || sudo dhclient -v \"$IFACE\" || sudo dhclient -v eth0",
    "ip -br a",
]
for c in cmds:
    text(c)
    send("KEY_ENTER")
    time.sleep(3.5)

print("seeded; check: virsh -c qemu:///system net-dhcp-leases vagrant-libvirt")
PY

echo "--- leases ---"
virsh -c qemu:///system net-dhcp-leases vagrant-libvirt || true
