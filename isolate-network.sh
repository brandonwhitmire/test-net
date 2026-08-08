#!/usr/bin/env bash
# Hypervisor-level internet isolation for internal lab targets.
#
# Turns the management NIC (vagrant-libvirt NAT) off from outside the guest so
# malware inside dc / linux / ws01 cannot re-enable it. Kali is never touched.
#
# Lab traffic stays on pentest-lab (forward_mode none — no NAT). seal-lab both
# ensures that and unplugs target management NICs so the estate is fully sealed.
#
# USAGE:
#   ./isolate-network.sh seal-lab         Seal the lab (isolated net + mgmt NICs off)
#   ./isolate-network.sh off [vm...]      Unplug management NIC on targets only
#   ./isolate-network.sh on  [vm...]      Replug management NIC on targets
#   ./isolate-network.sh status [vm...]   Show management link + lab forward mode
#   ./isolate-network.sh help

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# Internal estate only — never touch kali.
TARGET_DEFAULTS=(dc linux ws01)
ALL_LAB_VMS=(dc linux ws01 kali)

LAB_NETWORK="${LAB_NETWORK:-pentest-lab}"
MGMT_NETWORK="${MGMT_NETWORK:-vagrant-libvirt}"
LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
LAB_BRIDGE_IP="${LAB_BRIDGE_IP:-10.0.0.1}"
LAB_NETMASK="${LAB_NETMASK:-255.255.255.0}"

PROJECT_PREFIX="$(basename "$REPO_ROOT")"

COMMAND=""
TARGET_VMS=()

usage() {
  cat <<EOF
Hypervisor internet isolation (libvirt management NIC link).

USAGE:
  ./isolate-network.sh seal-lab      Seal the lab: isolated ${LAB_NETWORK} + unplug target mgmt NICs
  ./isolate-network.sh off [vm...]   Unplug management NIC only (default: ${TARGET_DEFAULTS[*]})
  ./isolate-network.sh on  [vm...]   Restore management NIC (internet back on targets)
  ./isolate-network.sh status [vm...]
  ./isolate-network.sh help

Kali stays dual-homed (${MGMT_NETWORK} + ${LAB_NETWORK}) and is never modified.

While sealed, host forwarded ports (localhost:5985, :8888, …) stop working
because they ride the management NIC — use lab IPs (e.g. http://10.0.0.20:5601).
EOF
}

virsh_c() {
  virsh -c "$LIBVIRT_URI" "$@"
}

is_target_vm() {
  local candidate="$1" vm
  for vm in "${TARGET_DEFAULTS[@]}"; do
    [[ "$vm" == "$candidate" ]] && return 0
  done
  return 1
}

resolve_targets() {
  if [[ $# -eq 0 ]]; then
    TARGET_VMS=("${TARGET_DEFAULTS[@]}")
    return
  fi
  TARGET_VMS=()
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "kali" ]]; then
      echo "[!] Refusing to isolate kali — it must stay dual-homed." >&2
      exit 1
    fi
    if ! is_target_vm "$arg"; then
      echo "[!] Unknown target '$arg'. Known: ${TARGET_DEFAULTS[*]}" >&2
      exit 1
    fi
    TARGET_VMS+=("$arg")
  done
}

domain_name() {
  echo "${PROJECT_PREFIX}_$1"
}

domstate() {
  virsh_c domstate "$(domain_name "$1")" 2>/dev/null || true
}

domain_running() {
  local state
  state="$(domstate "$1")"
  [[ "$state" == *running* || "$state" == *ejecutando* ]]
}

mgmt_iface() {
  local domain="$1"
  virsh_c domiflist "$domain" | awk -v net="$MGMT_NETWORK" '$3 == net { print $1; exit }'
}

lab_forward_mode() {
  local xml
  xml="$(virsh_c net-dumpxml "$LAB_NETWORK" 2>/dev/null || true)"
  [[ -z "$xml" ]] && return 0
  # No <forward> element means isolated (libvirt omits mode='none' in dumpxml).
  if ! grep -q '<forward[[:space:]]' <<<"$xml"; then
    echo "none"
    return 0
  fi
  sed -n "s/.*<forward mode='\([^']*\)'.*/\1/p" <<<"$xml" | head -1
}

warn_if_lab_nats() {
  local mode
  mode="$(lab_forward_mode || true)"
  if [[ -z "${mode:-}" ]]; then
    echo "[!] ${LAB_NETWORK} is not defined yet — next vagrant up will create it (forward=none)."
    return
  fi
  if [[ "$mode" != "none" && "$mode" != "isolated" ]]; then
    echo
    echo "[!] ${LAB_NETWORK} forward=${mode} — lab NAT still exists."
    echo "    Malware could regain internet via ${LAB_BRIDGE_IP} until you run:"
    echo "      ./isolate-network.sh seal-lab"
  fi
}

set_mgmt_link() {
  local vm="$1" state="$2"
  local domain iface
  domain="$(domain_name "$vm")"
  if ! domain_running "$vm"; then
    echo "[!] $vm ($domain): not running — skip"
    return 0
  fi
  iface="$(mgmt_iface "$domain" || true)"
  if [[ -z "${iface:-}" ]]; then
    echo "[!] $vm: no ${MGMT_NETWORK} NIC found" >&2
    return 1
  fi
  virsh_c domif-setlink "$domain" "$iface" "$state" >/dev/null
  echo "[+] $vm: ${MGMT_NETWORK} ($iface) → $state"
}

show_mgmt_link() {
  local vm="$1"
  local domain iface link
  domain="$(domain_name "$vm")"
  if ! domain_running "$vm"; then
    echo "  $vm: not running ($(domstate "$vm" | tr -d '\n' || echo unknown))"
    return 0
  fi
  iface="$(mgmt_iface "$domain" || true)"
  if [[ -z "${iface:-}" ]]; then
    echo "  $vm: no ${MGMT_NETWORK} NIC"
    return 0
  fi
  link="$(virsh_c domif-getlink "$domain" "$iface" 2>/dev/null | awk '{print $2}')"
  echo "  $vm: ${MGMT_NETWORK} $iface is ${link:-unknown}"
}

cmd_off() {
  local vm
  echo "[*] Unplugging management NICs on targets (hypervisor)..."
  for vm in "${TARGET_VMS[@]}"; do
    set_mgmt_link "$vm" down
  done
  echo
  warn_if_lab_nats
  echo "[+] Targets cut off from the internet at the hypervisor."
  echo "    Kali unchanged. Lab ${LAB_NETWORK} still links the VMs."
}

cmd_on() {
  local vm
  echo "[*] Restoring management NICs on targets..."
  for vm in "${TARGET_VMS[@]}"; do
    set_mgmt_link "$vm" up
  done
  echo "[+] Targets can reach the internet again via ${MGMT_NETWORK}."
}

cmd_status() {
  local vm mode
  echo "Internet isolation status:"
  for vm in "${TARGET_VMS[@]}"; do
    show_mgmt_link "$vm"
  done
  mode="$(lab_forward_mode || true)"
  if [[ -z "${mode:-}" ]]; then
    echo "  ${LAB_NETWORK}: (not defined)"
  else
    echo "  ${LAB_NETWORK}: forward=${mode}"
  fi
  warn_if_lab_nats
}

define_isolated_lab_net() {
  local xml
  xml="$(mktemp)"
  cat >"$xml" <<EOF
<network>
  <name>${LAB_NETWORK}</name>
  <forward mode='none'/>
  <bridge name='virbr-pentest' stp='on' delay='0'/>
  <ip address='${LAB_BRIDGE_IP}' netmask='${LAB_NETMASK}'/>
</network>
EOF
  virsh_c net-define "$xml" >/dev/null
  rm -f "$xml"
}

unplug_target_mgmt() {
  local vm
  TARGET_VMS=("${TARGET_DEFAULTS[@]}")
  echo "[*] Unplugging management NICs on targets..."
  for vm in "${TARGET_VMS[@]}"; do
    set_mgmt_link "$vm" down
  done
}

cmd_seal_lab() {
  local vm mode
  mode="$(lab_forward_mode || true)"

  if [[ "$mode" != "none" && "$mode" != "isolated" ]]; then
    echo "[*] Recreating ${LAB_NETWORK} as isolated (no NAT)."
    echo "    This briefly halts all lab VMs: ${ALL_LAB_VMS[*]}"
    if [[ "${FORCE:-}" != "1" ]]; then
      read -r -p "    Continue? [y/N] " ans
      [[ "${ans:-}" =~ ^[Yy]$ ]] || { echo "[!] Aborted."; exit 1; }
    fi

    for vm in "${ALL_LAB_VMS[@]}"; do
      if domain_running "$vm"; then
        echo "[*] Halting $vm..."
        vagrant halt "$vm" || true
      fi
    done

    if virsh_c net-info "$LAB_NETWORK" >/dev/null 2>&1; then
      virsh_c net-destroy "$LAB_NETWORK" 2>/dev/null || true
      virsh_c net-undefine "$LAB_NETWORK" 2>/dev/null || true
    fi

    define_isolated_lab_net
    virsh_c net-start "$LAB_NETWORK" >/dev/null
    echo "[+] ${LAB_NETWORK} is isolated (no NAT). Host gateway ${LAB_BRIDGE_IP} remains for lab access."

    echo "[*] Bringing VMs back (no re-provision)..."
    vagrant up --no-provision
  else
    echo "[*] ${LAB_NETWORK} already isolated (forward=${mode:-none})."
  fi

  unplug_target_mgmt
  echo
  echo "[+] Lab sealed: targets have no internet (mgmt NICs down, lab net has no NAT)."
  echo "    Kali unchanged (dual-homed). Use ./isolate-network.sh on to restore target internet."
}

# --- argv ---
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  off|on|status)
    resolve_targets "$@"
    ;;
  seal-lab)
    ;;
  help|-h|--help)
    usage
    exit 0
    ;;
  *)
    echo "[!] Unknown command: $COMMAND" >&2
    usage >&2
    exit 1
    ;;
esac

case "$COMMAND" in
  off) cmd_off ;;
  on) cmd_on ;;
  status) cmd_status ;;
  seal-lab) cmd_seal_lab ;;
esac
