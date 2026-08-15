#!/bin/sh
# Runs inside /target via debian-installer late_command.
# Never abort d-i: every step is attempted, failures are recorded, exit is always 0.
#
# After first boot:
#   cat /var/log/preseed-late.log
#   cat /root/preseed-late.log
# From the installer shell (Alt-F2) before reboot:
#   cat /target/var/log/preseed-late.log
#   cat /target/tmp/preseed-late.log
#   cat /target/tmp/preseed-late-wrapper.log

LOG_VAR=/var/log/preseed-late.log
LOG_ROOT=/root/preseed-late.log
LOG_TMP=/tmp/preseed-late.log
FAILED=

mkdir -p /var/log /root /tmp /etc/sudoers.d /etc/apt/sources.list.d \
  /etc/systemd/network /etc/systemd/system/multi-user.target.wants \
  /etc/systemd/system/sockets.target.wants

: >"$LOG_TMP"
exec >>"$LOG_TMP" 2>&1

sync_logs() {
  cp -f "$LOG_TMP" "$LOG_VAR" 2>/dev/null || true
  cp -f "$LOG_TMP" "$LOG_ROOT" 2>/dev/null || true
}

trap 'sync_logs' EXIT INT TERM

echo "==== preseed late-command start $(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown) ===="
echo "shell=$0 pid=$$"
cat /etc/os-release 2>/dev/null || true
uname -a 2>/dev/null || true
command -v systemctl >/dev/null && systemctl --version | head -n 1 || echo "no systemctl"
echo "---- unit files ----"
ls -l /lib/systemd/system/ssh* /usr/lib/systemd/system/ssh* \
  /lib/systemd/system/systemd-networkd* /usr/lib/systemd/system/systemd-networkd* \
  /lib/systemd/system/qemu-guest-agent* /usr/lib/systemd/system/qemu-guest-agent* \
  2>/dev/null || true

step() {
  name=$1
  shift
  echo
  echo "---- BEGIN $name ----"
  echo "+ $*"
  if "$@"; then
    echo "OK    $name"
    return 0
  fi
  rc=$?
  echo "FAIL  $name rc=$rc"
  FAILED="${FAILED} ${name}"
  return "$rc"
}

enable_unit() {
  unit=$1
  for dir in /usr/lib/systemd/system /lib/systemd/system; do
    if [ -f "$dir/$unit" ]; then
      echo "found $dir/$unit"
      if systemctl enable --offline "$unit"; then
        return 0
      fi
      echo "systemctl enable --offline failed, trying systemctl enable"
      if systemctl enable "$unit"; then
        return 0
      fi
      echo "systemctl enable failed, linking into multi-user.target.wants"
      ln -sfn "$dir/$unit" "/etc/systemd/system/multi-user.target.wants/$unit"
      return 0
    fi
  done
  echo "missing unit file $unit"
  return 1
}

step enable-ssh enable_unit ssh.service \
  || step enable-ssh-socket enable_unit ssh.socket

step write-sudoers sh -c "printf '%s\n' 'vagrant ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-vagrant"
step chmod-sudoers chmod 0440 /etc/sudoers.d/10-vagrant

step write-apt-sources sh -c "printf '%s\n' \
  'Types: deb' \
  'URIs: http://http.kali.org/kali/' \
  'Suites: kali-rolling' \
  'Components: main contrib non-free non-free-firmware' \
  'Signed-By: /usr/share/keyrings/kali-archive-keyring.gpg' \
  > /etc/apt/sources.list.d/kali.sources"

step enable-qemu-ga enable_unit qemu-guest-agent.service

step write-networkd sh -c "printf '%s\n' \
  '[Match]' \
  'Name=eth0' \
  '[Network]' \
  'DHCP=yes' \
  > /etc/systemd/network/20-mgmt-eth0.network"

step enable-networkd enable_unit systemd-networkd.service

if [ -f /etc/network/interfaces ]; then
  echo
  echo "---- /etc/network/interfaces before ----"
  cat /etc/network/interfaces
  step comment-ifupdown sed -i \
    -e 's/^allow-hotplug eth0/#allow-hotplug eth0/' \
    -e 's/^iface eth0 inet dhcp/#iface eth0 inet dhcp/' \
    /etc/network/interfaces
  echo "---- /etc/network/interfaces after ----"
  cat /etc/network/interfaces
else
  echo "no /etc/network/interfaces (ok)"
fi

echo
echo "==== preseed late-command done ===="
if [ -n "$FAILED" ]; then
  echo "failed steps:$FAILED"
else
  echo "failed steps: none"
fi
echo "logs: $LOG_VAR $LOG_ROOT $LOG_TMP"

sync_logs
exit 0
