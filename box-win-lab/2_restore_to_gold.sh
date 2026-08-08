#!/bin/bash
#
# This script resets the VM to the 'gold_image' snapshot.
# It halts the machine and then restores the clean state.
#
# USAGE:
#   ./2_restore_to_gold.sh        (Runs in interactive mode, will ask for confirmation)
#   ./2_restore_to_gold.sh -f     (Runs in non-interactive mode, restores without asking)
#   ./2_restore_to_gold.sh --force (Same as -f)
#

# Exit immediately if any command fails
set -e

# --- Load shared configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/5_config"

# --- Get current snapshot list ---
display_snapshot_list

# --- Argument Parsing ---
FORCE_MODE=false
if [[ "$1" == "-f" || "$1" == "--force" ]]; then
  FORCE_MODE=true
  echo "[!] Force mode enabled. The VM will be restored without confirmation."
fi

# --- Confirmation Logic ---
if [ "$FORCE_MODE" = false ]; then
  read -p "    -> This will DESTROY all current changes to the VM. Are you sure? (y/n) " -n 1 -r
  echo # Move to a new line

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "[!] Aborted by user. The VM was halted but not restored."
    exit 1
  fi
fi

# --- Main Workflow ---
echo "[*] Step 1: Halting the VM to prepare for restore..."
vagrant halt

echo "[*] Step 2: Preparing to restore the '$SNAPSHOT_NAME' snapshot..."

# --- Restore Execution ---
echo "    -> Restoring snapshot '$SNAPSHOT_NAME'..."
# Vagrant's own confirmation is bypassed by our script's logic,
# but we add -f to the command itself for non-interactive environments.
yes | vagrant snapshot restore $SNAPSHOT_NAME

echo
echo "[+] SUCCESS: The VM has been reset to the '$SNAPSHOT_NAME' state."
echo "    To boot the clean machine, run:"
echo "     vagrant up"
