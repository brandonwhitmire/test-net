#!/usr/bin/env bash
# Build the Kali golden Vagrant box (kali-box) with Packer + UEFI.
# Run from this directory: kali/packer/
set -euo pipefail

BASE_URL="https://kali.download/base-images/current"
SUMS_URL="${BASE_URL}/SHA256SUMS"
TMPDIR_DEFAULT="${HOME}/.cache/packer/"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

line="$(curl -fsSL "${SUMS_URL}" | awk '/kali-linux-[0-9]+\.[0-9]+-installer-amd64\.iso$/ {print; exit}')"
if [[ -z "${line}" ]]; then
  echo "Could not find latest Kali installer ISO in ${SUMS_URL}" >&2
  exit 1
fi

checksum="$(awk '{print $1}' <<< "${line}")"
filename="$(awk '{print $2}' <<< "${line}")"
iso_url="${BASE_URL}/${filename}"

export PKR_VAR_kali_iso_url="${iso_url}"
export PKR_VAR_kali_iso_checksum="sha256:${checksum}"

echo "[*] ISO: ${iso_url}"
echo "[*] Checksum: sha256:${checksum}"

# Built Kali artifacts are large — keep TMPDIR off small /tmp
mkdir -p "${TMPDIR_DEFAULT}"
export TMPDIR="${TMPDIR:-${TMPDIR_DEFAULT}}"

packer init . 2>/dev/null || true
packer build "$@" .

echo
echo "[+] Done. Register the box:"
echo "    vagrant box add -f kali-box output-kali/kali-box-libvirt-1.0.box"
