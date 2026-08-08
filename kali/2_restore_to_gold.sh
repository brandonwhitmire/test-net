#!/bin/bash
# Reset the factory VM to the 'gold_image_kali' snapshot.
#
# USAGE:
#   ./2_restore_to_gold.sh
#   ./2_restore_to_gold.sh -f|--force

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=5_config
source "$SCRIPT_DIR/5_config"
cd "$SCRIPT_DIR"

display_snapshot_list

FORCE_MODE=false
if [[ "${1:-}" == "-f" || "${1:-}" == "--force" ]]; then
  FORCE_MODE=true
  echo "[!] Force mode enabled. The VM will be restored without confirmation."
fi

if [[ "$FORCE_MODE" = false ]]; then
  read -r -p "    -> This will DESTROY all current changes to the factory VM. Are you sure? (y/n) " -n 1
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "[!] Aborted by user."
    exit 1
  fi
fi

echo "[*] Step 1: Halting the VM..."
vagrant halt
echo "[*] Step 2: Restoring snapshot '$SNAPSHOT_NAME'..."
yes | vagrant snapshot restore "$SNAPSHOT_NAME"

echo
echo "[+] SUCCESS: Factory VM reset to '$SNAPSHOT_NAME'."
echo "    Boot with: vagrant up"
