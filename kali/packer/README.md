# Packer — Kali attacker golden box (`kali-box`)
#
# Moved here from [personal-packer](https://github.com/brandonwhitmire/personal-packer)
# (`kali.pkr.hcl` + `resources/kali-preseed.cfg`). Build is **UEFI / OVMF**.

## Prerequisites

```bash
sudo pacman -S packer edk2-ovmf
packer plugins install github.com/hashicorp/qemu
```

**Important:** never point libvirt NVRAM at `/usr/share/edk2/x64/OVMF_VARS.4m.fd` (it gets overwritten/deleted). This repo vendors a template at `ovmf/OVMF_VARS.4m.fd`. If your system file is missing:

```bash
sudo cp ovmf/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd
```

## Build + register

```bash
cd kali/packer
chmod +x build.sh
./build.sh
vagrant box add -f kali-box output-kali/kali-box-libvirt-1.0.box
```

## Debugging a build

```bash
PACKER_LOG=1 ./build.sh -on-error=ask
```

`headless = false`, so **watch the QEMU window** — it is the only real feedback. Packer itself just prints `Waiting for SSH to become available...` for the whole install.

`Timeout waiting for SSH` almost always means one of:

| What you see in the QEMU window | Cause |
| ---- | ---- |
| An installer error dialog, waiting for input | The wrapper now always exits 0, so this should not happen. If it does, Alt-F2 and `cat /target/tmp/preseed-late-wrapper.log`. After boot: `cat /var/log/preseed-late.log` (copy also at `/root/preseed-late.log`). |
| Installer still copying/downloading packages | Genuinely slower than `ssh_timeout` (now `60m`). Slow mirror. |
| A login prompt, install finished | SSH did not start, or `net.ifnames`/NIC naming left the box with no DHCP lease. |
| Still at the boot menu / grub prompt | `boot_command` did not land. Bump `boot_wait` / `boot_key_interval`. |

`-on-error=ask` leaves the VM running so you can inspect it instead of deleting the output directory.

## Lab usage

Root `Vagrantfile` boots this box with OVMF (private NVRAM under `.vagrant/`):

```bash
# From repo root
vagrant up kali && vagrant ssh kali
```

Lab-wide gold snapshots: [`../../snapshot.sh`](../../snapshot.sh).
