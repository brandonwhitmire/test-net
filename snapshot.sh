#!/usr/bin/env bash
# Lab VM gold-snapshot management for the repo-root Vagrantfile.
#
# USAGE:
#   ./snapshot.sh take|save [-f] [--halt] [vm...]  Save gold snapshot in current state (optional --halt)
#   ./snapshot.sh restore [-f] [vm...]             Restore gold snapshot (discard current state)
#   ./snapshot.sh overwrite [-f] [--halt] [vm...]  Overwrite gold from current state (optional --halt)
#   ./snapshot.sh delete [-f] [vm...]              Delete gold snapshot
#   ./snapshot.sh list [vm...]                     Check whether gold snapshots exist
#   ./snapshot.sh help

set -euo pipefail

# =============================================================================
# Config
# =============================================================================

# Machines defined in the root Vagrantfile (order matters for first-time bring-up).
LAB_VMS=(dc linux ws01 kali)

# Snapshot name saved on every machine after a successful build.
SNAPSHOT_NAME="gold"

# =============================================================================
# Bootstrap
# =============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

FORCE_MODE=false
HALT_BEFORE_SNAPSHOT=false
COMMAND=""
TARGET_VMS=()

# =============================================================================
# Helpers
# =============================================================================

usage() {
  cat <<EOF
Lab VM gold-snapshot management for the repo-root Vagrantfile.

USAGE:
  ./snapshot.sh take|save [-f] [--halt] [vm...]  Save gold snapshot in current state (--halt first)
  ./snapshot.sh restore [-f] [vm...]             Restore gold snapshot (discard current state)
  ./snapshot.sh overwrite [-f] [--halt] [vm...]  Overwrite gold from current state (--halt first)
  ./snapshot.sh delete [-f] [vm...]              Delete gold snapshot
  ./snapshot.sh list [vm...]                     Check whether gold snapshots exist
  ./snapshot.sh help

VMs: ${LAB_VMS[*]}
EOF
}

is_lab_vm() {
  local candidate="$1"
  local vm
  for vm in "${LAB_VMS[@]}"; do
    [[ "$vm" == "$candidate" ]] && return 0
  done
  return 1
}

resolve_targets() {
  if [[ $# -eq 0 ]]; then
    TARGET_VMS=("${LAB_VMS[@]}")
    return
  fi
  TARGET_VMS=()
  local arg
  for arg in "$@"; do
    if ! is_lab_vm "$arg"; then
      echo "[!] Unknown VM '$arg'. Known: ${LAB_VMS[*]}" >&2
      exit 1
    fi
    TARGET_VMS+=("$arg")
  done
}

snapshot_exists() {
  local vm="$1"
  local snapshot_to_check="${2:-$SNAPSHOT_NAME}"
  local list
  list="$(vagrant snapshot list "$vm" 2>/dev/null || true)"
  echo "$list" | grep -qE "^[[:space:]]*${snapshot_to_check}([[:space:]]|$)"
}

display_snapshot_status() {
  local vm
  echo "[*] Checking '$SNAPSHOT_NAME' snapshots..."
  for vm in "${TARGET_VMS[@]}"; do
    if snapshot_exists "$vm"; then
      echo "[+] $vm: Snapshot exists"
    else
      echo "[!] $vm: NO snapshot found"
    fi
  done
  echo
}

confirm_or_abort() {
  local prompt="$1"
  if [[ "$FORCE_MODE" == true ]]; then
    return 0
  fi
  read -r -p "    -> ${prompt} (y/n) " -n 1
  echo
  if [[ ! ${REPLY:-} =~ ^[Yy]$ ]]; then
    echo "[!] Aborted by user."
    exit 1
  fi
}

confirm_overwrite_snapshots() {
  local vm
  local any_exists=false
  for vm in "${TARGET_VMS[@]}"; do
    if snapshot_exists "$vm"; then
      any_exists=true
      break
    fi
  done
  if [[ "$any_exists" == true ]]; then
    confirm_or_abort "This will overwrite existing '$SNAPSHOT_NAME' snapshot(s). Are you sure?"
  else
    echo "[*] No existing '$SNAPSHOT_NAME' snapshot found on target VMs. Proceeding..."
  fi
}

halt_targets() {
  local vm
  for vm in "${TARGET_VMS[@]}"; do
    echo "[*] Halting '$vm'..."
    vagrant halt "$vm" || true
  done
}

save_snapshot() {
  local vm="$1"
  if vagrant snapshot save "$vm" "$SNAPSHOT_NAME" --force >/dev/null 2>&1; then
    echo "[+] $vm: Snapshot saved"
    return 0
  fi
  echo "[!] $vm: Failed to save snapshot" >&2
  return 1
}

delete_snapshot() {
  local vm="$1"
  if vagrant snapshot delete "$vm" "$SNAPSHOT_NAME" >/dev/null 2>&1; then
    echo "[+] $vm: Snapshot deleted"
    return 0
  fi
  echo "[!] $vm: Failed to delete snapshot" >&2
  return 1
}

restore_snapshot() {
  local vm="$1"
  # --no-tty answers the restore confirmation; avoid `yes |` which trips pipefail (SIGPIPE).
  if vagrant snapshot restore --no-tty "$vm" "$SNAPSHOT_NAME" >/dev/null 2>&1; then
    echo "[+] $vm: Snapshot restored"
    return 0
  fi
  echo "[!] $vm: Failed to restore snapshot" >&2
  return 1
}

# Returns 0 if the VM has been created (any state other than not_created).
vm_created() {
  local vm="$1"
  local state
  state="$(vagrant status --machine-readable "$vm" 2>/dev/null \
    | awk -F',' -v name="$vm" '$2 == name && $3 == "state" { print $4; exit }')"
  [[ -n "$state" && "$state" != "not_created" ]]
}

# =============================================================================
# Commands
# =============================================================================

cmd_take() {
  resolve_targets "$@"
  display_snapshot_status
  if [[ "$FORCE_MODE" == true ]]; then
    echo "[!] Force mode enabled. Snapshots will be overwritten without confirmation."
  else
    confirm_overwrite_snapshots
  fi

  local vm
  local missing=()
  for vm in "${TARGET_VMS[@]}"; do
    if vm_created "$vm"; then
      echo "[*] '$vm' already exists — skipping provision"
    else
      missing+=("$vm")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[*] Step 1: Creating and provisioning: ${missing[*]}"
    vagrant up --provision "${missing[@]}"
  else
    echo "[*] Step 1: All target VMs already exist — skipping provision"
  fi

  local step=2
  if [[ "$HALT_BEFORE_SNAPSHOT" == true ]]; then
    echo "[*] Step ${step}: Halting VMs before snapshot..."
    halt_targets
    step=$((step + 1))
  else
    echo "[*] Skipping halt — snapshotting VMs in their current state"
  fi

  echo "[*] Step ${step}: Saving snapshot '$SNAPSHOT_NAME'..."
  for vm in "${TARGET_VMS[@]}"; do
    echo "    -> $vm"
    if ! save_snapshot "$vm"; then
      exit 1
    fi
  done

  echo
  echo "[+] SUCCESS: Snapshot '$SNAPSHOT_NAME' created for: ${TARGET_VMS[*]}"
}

cmd_restore() {
  resolve_targets "$@"

  if [[ "$FORCE_MODE" == true ]]; then
    echo "[!] Force mode enabled. VMs will be restored without confirmation."
  else
    confirm_or_abort "This will DESTROY all current changes on: ${TARGET_VMS[*]}. Are you sure?"
  fi

  echo "[*] Restoring snapshot '$SNAPSHOT_NAME'..."
  local vm
  local failed=0
  for vm in "${TARGET_VMS[@]}"; do
    restore_snapshot "$vm" || failed=1
  done

  if [[ "$failed" -ne 0 ]]; then
    echo "[!] One or more restores failed." >&2
    exit 1
  fi
  echo "[+] SUCCESS: Restored '$SNAPSHOT_NAME' on: ${TARGET_VMS[*]}"
}

cmd_overwrite() {
  resolve_targets "$@"
  if [[ "$FORCE_MODE" == true ]]; then
    echo "[!] Force mode enabled. Snapshots will be overwritten without confirmation."
  else
    confirm_or_abort "This will overwrite '$SNAPSHOT_NAME' on: ${TARGET_VMS[*]}. Are you sure?"
  fi

  local step=1
  if [[ "$HALT_BEFORE_SNAPSHOT" == true ]]; then
    echo "[*] Step ${step}: Halting VMs before snapshot..."
    halt_targets
    step=$((step + 1))
  else
    echo "[*] Skipping halt — snapshotting VMs in their current state"
  fi

  echo "[*] Step ${step}: Saving snapshot '$SNAPSHOT_NAME'..."
  local vm
  local failed=0
  for vm in "${TARGET_VMS[@]}"; do
    save_snapshot "$vm" || failed=1
  done

  if [[ "$failed" -ne 0 ]]; then
    echo "[!] One or more overwrites failed." >&2
    exit 1
  fi
  echo "[+] SUCCESS: Snapshot '$SNAPSHOT_NAME' overwritten for: ${TARGET_VMS[*]}"
}

cmd_delete() {
  resolve_targets "$@"
  display_snapshot_status

  local vm
  local to_delete=()
  for vm in "${TARGET_VMS[@]}"; do
    if snapshot_exists "$vm"; then
      to_delete+=("$vm")
    fi
  done

  if [[ ${#to_delete[@]} -eq 0 ]]; then
    echo "[*] Nothing to delete — no '$SNAPSHOT_NAME' snapshots on target VMs."
    return 0
  fi

  if [[ "$FORCE_MODE" == true ]]; then
    echo "[!] Force mode enabled. Snapshots will be deleted without confirmation."
  else
    confirm_or_abort "This will DELETE '$SNAPSHOT_NAME' on: ${to_delete[*]}. Are you sure?"
  fi

  echo "[*] Deleting snapshot '$SNAPSHOT_NAME'..."
  for vm in "${to_delete[@]}"; do
    if ! delete_snapshot "$vm"; then
      exit 1
    fi
  done

  echo
  echo "[+] SUCCESS: Deleted '$SNAPSHOT_NAME' on: ${to_delete[*]}"
}

cmd_list() {
  resolve_targets "$@"
  display_snapshot_status
}

# =============================================================================
# Main
# =============================================================================

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE_MODE=true
      shift
      ;;
    --halt)
      HALT_BEFORE_SNAPSHOT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "[!] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ ${#args[@]} -eq 0 ]]; then
  usage >&2
  exit 1
fi

COMMAND="${args[0]}"
unset 'args[0]'
rest=()
for a in "${args[@]+"${args[@]}"}"; do
  rest+=("$a")
done

case "$COMMAND" in
  take|save) cmd_take "${rest[@]+"${rest[@]}"}" ;;
  restore)   cmd_restore "${rest[@]+"${rest[@]}"}" ;;
  overwrite) cmd_overwrite "${rest[@]+"${rest[@]}"}" ;;
  delete)    cmd_delete "${rest[@]+"${rest[@]}"}" ;;
  list)      cmd_list "${rest[@]+"${rest[@]}"}" ;;
  help)      usage ;;
  *)
    echo "[!] Unknown command: $COMMAND" >&2
    usage >&2
    exit 1
    ;;
esac
