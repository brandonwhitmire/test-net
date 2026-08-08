#!/bin/bash
# Create the 'gold_image_kali' snapshot for this factory Vagrantfile.
#
# USAGE:
#   ./1_create_gold_image.sh
#   ./1_create_gold_image.sh -f|--force

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=5_config
source "$SCRIPT_DIR/5_config"
cd "$SCRIPT_DIR"

display_snapshot_list

FORCE_MODE=false
if [[ "${1:-}" == "-f" || "${1:-}" == "--force" ]]; then
  FORCE_MODE=true
  echo "[!] Force mode enabled. The snapshot will be overwritten without confirmation."
else
  if snapshot_exists; then
    echo "[*] '$SNAPSHOT_NAME' already exists!"
    read -r -p "    -> This will overwrite the existing '$SNAPSHOT_NAME' snapshot. Are you sure? (y/n) " -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "[!] Aborted by user. No snapshot was taken."
      exit 1
    fi
  else
    echo "[*] No existing '$SNAPSHOT_NAME' snapshot found. Proceeding with creation..."
  fi
fi

echo "[*] Step 1: Provisioning the VM with 'vagrant up'..."
if [[ -f .venv/bin/activate ]]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi
vagrant up --provision
echo "[*] Step 2: Halting the VM for a clean snapshot..."
vagrant halt
echo "[*] Step 3: Saving snapshot '$SNAPSHOT_NAME'..."
vagrant snapshot save "$SNAPSHOT_NAME" --force

echo
echo "[+] SUCCESS: Gold image snapshot created."
echo "    Optional — package for the lab Vagrantfile:"
echo "      vagrant up && vagrant package --output kali-box.box"
echo "      vagrant box add -f kali-box kali-box.box"
echo "    Then from repo root: vagrant up kali"
