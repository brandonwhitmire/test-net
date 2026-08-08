# Kali attacker — golden box + Packer + lab integration

External to `lab.local` (no domain join, no Sysmon/ELK). Lives on `pentest-lab` at **10.0.0.50**.

## Layout

| Path | Role |
| ---- | ---- |
| `packer/` | Packer UEFI build → `kali-box` (from personal-packer) |
| `files/lab-network.sh` | Provisioner: eth1 `10.0.0.50` only (see note below) |
| `seed-mgmt-dhcp.sh` | Rescue for a `vagrant up` hung on the IP wait |
| `0_run_attacker_box.sh` | `vagrant up kali` + SSH from repo root |
| `1_` / `2_` / `3_` + `5_config` | Snapshot / gold helpers for the factory VM |
| `roles/` | Attacker roles: `base`, `desktop`, `development`, `security_tools` |
| `kalilinux.yml` | Gold-image factory entrypoint (runs those roles on the factory VM) |

## Quick start (lab)

```bash
# From repo root — requires registered kali-box
vagrant up kali && vagrant ssh kali
```

Provisioning runs in two steps: `files/lab-network.sh` adds the lab IP on eth1, then Ansible applies `ansible/playbooks/attackers.yml`. That playbook runs the same `roles/` used by the gold-image factory (`base`, `desktop`, `development`, `security_tools`) plus `kali_attacker` for lab wiring — they are shared via `roles_path` in `ansible/ansible.cfg`, not copied.

```bash
vagrant provision kali

# standalone
cd ansible && ansible-playbook playbooks/attackers.yml

# lab wiring only (seconds, skips the tooling build)
cd ansible && ansible-playbook playbooks/attackers.yml --tags lab
```

The full run installs XFCE, Metasploit, BloodHound, SecLists and friends, so it takes a while on a Packer box that was never through the factory. `--tags image` is the build half, `--tags lab` the config half.

Tune the lab side in `ansible/inventory/group_vars/attackers.yml` — `kali_use_lab_dns` to resolve via the DC, `kali_extra_packages` for one-off additions. The attacker is intentionally left out of `site.yml`.

## Management NIC (eth0) — why it is not provisioned

`vagrant up` blocks on “Waiting for domain to get an IP address…” until **eth0 gets a DHCP lease** on the `vagrant-libvirt` network. A running SPICE desktop does not count.

Nothing in this repo can fix that from the outside: provisioners run over SSH, and that SSH goes over eth0. **eth0 DHCP must already work in the box image.** That is why `lab-network.sh` only configures eth1 — touching the management link mid-provision drops Vagrant's own connection (`EHOSTUNREACH`).

**Unstick a hung `vagrant up`** — in the Kali GUI terminal:

```bash
# if systemd-networkd is already enabled (post-preseed fix):
sudo networkctl renew eth0
# otherwise one-shot DHCP with the binary that is already on the box:
sudo dhcpcd -4 eth0
```

**Why a fresh box has no IPv4 at all.** Kali follows Debian trixie, which dropped `isc-dhcp-client`. New installs get `dhcpcd-base` (Priority:important) — that is only the `dhcpcd` *binary*, with **no systemd unit to enable**. Meanwhile `debian-installer` still writes an ifupdown `iface eth0 inet dhcp` stanza that looks for `dhclient`, which no longer exists. Result: every interface stays unconfigured.

Modern Kali networking:

| Install type | Correct DHCP path |
| ---- | ---- |
| Desktop (XFCE etc.) | **NetworkManager** — ships its own DHCP client; configure with `nmcli` |
| This Packer minimal box | **systemd-networkd** — already part of systemd; write a `.network` file and `systemctl enable systemd-networkd` |

Do **not** `apt install dhcpcd` just to get a service — that fights ifupdown and is not the Kali-recommended path. The preseed enables systemd-networkd for eth0 and comments the broken ifupdown stanza out of `/etc/network/interfaces`.

References: [Debian trixie release notes](https://www.debian.org/releases/trixie/release-notes/issues.html), [SystemdNetworkd](https://wiki.debian.org/SystemdNetworkd), [NetworkConfiguration](https://wiki.debian.org/NetworkConfiguration).

**Fix it permanently** so the next `destroy`/`up` needs no babysitting — once SSH works, enable DHCP at boot and re-package:

```bash
vagrant ssh kali -c 'sudo systemctl enable --now dhcpcd'
vagrant halt kali
vagrant package kali --output kali-box.box
vagrant box add -f kali-box kali-box.box
```

Boxes built from `packer/` after the preseed fix already do this (NetworkManager profile for eth0 plus `net.ifnames=0` persisted in GRUB, so the NIC is `eth0` and not `enpXs0`).

## Rebuild the box

See [`packer/README.md`](packer/README.md).
