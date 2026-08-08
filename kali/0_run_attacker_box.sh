#!/bin/bash
# Start the lab Kali attacker (repo-root Vagrantfile) and open SSH.
# Gold-image snapshots are managed by 1_/2_/3_ scripts in this directory.
#
# USAGE:
#   ./0_run_attacker_box.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"
echo "[*] Bringing up lab attacker 'kali' on pentest-lab (10.0.0.50)..."
vagrant up kali
echo "[*] Opening SSH..."
vagrant ssh kali
