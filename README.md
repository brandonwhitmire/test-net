# Local pentest lab (libvirt / KVM)

Local AD + Sysmon + ELK lab. Vagrant manages VMs; Ansible configures them. Stages 1–4 complete.

```bash
vagrant up
cd ansible && ansible-playbook playbooks/health.yml
```

Site: https://brandonwhitmire.github.io/test-net/ (this README, built by Hugo).

## Architecture

| Layer | Tool | Job |
| ----- | ---- | --- |
| Lifecycle | Vagrant + libvirt/KVM + `snapshot.sh` | take/save / restore / overwrite / delete |
| Config | Ansible (host provisioner) | AD, Sysmon, ELK, shippers, Kali tooling |
| Images | Local Packer (rgl) + `kali/packer` | Windows boxes + `kali-box` — never Vagrant Cloud for Win/Kali |

### Data flow (Stage 3)

```
dc / ws01  --Winlogbeat-->  Elasticsearch :9200  <--Filebeat--  linux01 (sysmon syslog)
                                      |
                                   Kibana :5601
```

## Network

```
                    host (Arch)
                         |
              libvirt net: pentest-lab
                   10.0.0.0/24 (NAT)
      _____________|______________ ________
     |             |              |        |
 10.0.0.10    10.0.0.20      10.0.0.30  10.0.0.50
     dc         linux01          ws01      kali
  AD + DNS    Ubuntu/ELK      Win11 join  attacker
                                         (no domain)
```

- Domain: `lab.local` (alt: `lab.internal` if mDNS fights `.local`)
- Ubuntu box: `generic/ubuntu2204` **4.3.12**
- Windows boxes: local Packer from [rgl/windows-vagrant](https://github.com/rgl/windows-vagrant)
- Kali: local golden `kali-box` (Packer in `kali/packer/`) — not domain-joined, not logged
- Guest DNS → DC `10.0.0.10` (domain members only; kali is external)
- DHCP **disabled** on `pentest-lab` (static IPs only)
- Kibana: http://10.0.0.20:5601 · Elasticsearch: http://10.0.0.20:9200 (security off — lab net only)

## Credentials

| Account | Password | Where |
| ------- | -------- | ----- |
| `vagrant` | `vagrant` | WinRM / SSH / Vagrant |
| `Administrator` / `root` | `AdminUser123!!!` | Ansible after provision |
| `alice` / `bob` / `charlie` | `LabUser123!!!` | AD (Ansible) |

Vars: `ansible/inventory/group_vars/all.yml` ↔ `packer/lab.pkrvars.hcl` (keep synced).

## Prerequisites

```bash
# Host packages / plugins
sudo pacman -S vagrant libvirt qemu-desktop ebtables dnsmasq bridge-utils python-pywinrm ansible
vagrant plugin install vagrant-libvirt
vagrant plugin install vagrant-windows-sysprep   # required by rgl boxes

# Ansible collections
cd ansible && ansible-galaxy collection install -r requirements.yml
```

Build + register Windows boxes — see `packer/README.md`, or:

```bash
# In your rgl/windows-vagrant clone
make build-windows-2022-libvirt
vagrant box add -f windows-2022-amd64 windows-2022-amd64-libvirt.box

make build-windows-11-24h2-libvirt
vagrant box add -f windows-11-24h2-amd64 windows-11-24h2-amd64-libvirt.box
```

Confirm boxes:

```bash
vagrant box list | grep -E 'windows-2022|windows-11-24h2|ubuntu2204|kali-box'
```

## Machines

| Host (Vagrant) | Ansible | OS | IP | RAM | Role |
| -------------- | ------- | -- | -- | --- | ---- |
| `dc` | `dc` | Windows Server 2022 | 10.0.0.10 | 4 GB | AD DS + DNS (`lab.local`) |
| `linux` | `linux01` | Ubuntu 22.04 | 10.0.0.20 | 8 GB | Sysmon-for-Linux, ELK, Filebeat |
| `ws01` | `ws01` | Windows 11 24H2 | 10.0.0.30 | 4 GB | Domain-joined workstation |
| `kali` | `kali` | Kali (`kali-box`) | 10.0.0.50 | 4 GB | External attacker — no domain, no logging |

### Boxes

| Box | Source |
| --- | ------ |
| `windows-2022-amd64` | Local Packer: `make build-windows-2022-libvirt` |
| `windows-11-24h2-amd64` | Local Packer: `make build-windows-11-24h2-libvirt` |
| `generic/ubuntu2204` `4.3.12` | Vagrant Cloud (libvirt) |
| `kali-box` | Packer UEFI in `kali/packer/` (see `kali/README.md`) |

### Seeded AD

- OUs: `LabUsers`, `LabWorkstations`, `LabServers`, `LabGroups`
- Groups: `LabAdmins`, `HelpDesk`, `Developers`
- Users: `alice` (LabAdmins + Domain Admins), `bob` (HelpDesk), `charlie` (Developers) — password `LabUser123!!!`

## Layout

```
Vagrantfile
snapshot.sh                    # Gold snapshot / restore / overwrite all lab VMs
README.md                      # This file — also the GitHub Pages site
docs/                          # Hugo wrapper (mounts README.md)
.github/workflows/docs.yml
kali/                          # Attacker: Packer (UEFI kali-box), network bootstrap, roles
packer/{README.md,lab.pkrvars.hcl}
ansible/
  ansible.cfg
  requirements.yml
  inventory/hosts.yml
  inventory/group_vars/{all,domain_controllers,linux,workstations,attackers}.yml
  playbooks/{site,stage2,stage3,domain_controllers,linux,workstations,attackers,health}.yml
  roles/{ad_forest,ad_objects,domain_join,linux_base,windows_admin_password,windows_icmp,
         sysmon_windows,sysmon_linux,elk,winlogbeat,filebeat_sysmon,kibana_lab,kali_attacker}/
```

## Health check (all stages)

```bash
cd ansible
ansible-playbook playbooks/health.yml
```

Covers Stages 1–3 (reachability including Kali, AD/DNS/join, Sysmon, ELK + beat indices, Kibana Discover data views).

## Stage 1 — Core network

Promotes `dc` to AD DS (`lab.local`), seeds OUs/users/groups, joins `ws01`, points `linux` DNS at the DC, brings up `kali` on `10.0.0.50`.

```bash
# Bring up (serial: DC first — VAGRANT_NO_PARALLEL is set in Vagrantfile)
vagrant up

# Or stepwise
vagrant up dc
vagrant up linux
vagrant up ws01
vagrant up kali
```

Re-run Ansible only:

```bash
cd ansible
ansible-playbook playbooks/site.yml
# or per group:
ansible-playbook playbooks/domain_controllers.yml
ansible-playbook playbooks/linux.yml
ansible-playbook playbooks/workstations.yml
ansible-playbook playbooks/attackers.yml
```

### Verify

```bash
cd ansible
ansible-playbook playbooks/health.yml
```

Expect: all plays green (ICMP, WinRM/SSH, DNS, users/groups, domain join).

### Kali attacker

External to the domain (no join, no Sysmon/ELK). Same `pentest-lab` NAT net at **10.0.0.50**.

Box: local golden **`kali-box`** (UEFI/GPT — Vagrantfile boots it with OVMF).

```bash
vagrant up kali && vagrant ssh kali
```

On first create, Vagrant sets the lab IP on eth1 (`kali/files/lab-network.sh`) and then runs `ansible/playbooks/attackers.yml` — the `kali/roles/` toolset (`base`, `desktop`, `development`, `security_tools`) plus `kali_attacker` for lab wiring. It does not re-run on later `vagrant up`; use `vagrant provision kali` for that.

#### Build `kali-box` with Packer

Full from-scratch build: latest Kali installer ISO → preseeded UEFI install → Vagrant box. Takes a while (multi-GB ISO + install).

```bash
# One-time host prerequisites
sudo pacman -S packer edk2-ovmf
packer plugins install github.com/hashicorp/qemu

# Build (resolves the current ISO + checksum automatically)
cd kali/packer
./build.sh

# Register the result as kali-box
vagrant box add -f kali-box output-kali/kali-box-libvirt-1.0.box
```

Then from the repo root:

```bash
vagrant destroy -f kali
vagrant up kali
```

The preseed enables SSH, passwordless sudo, `qemu-guest-agent`, DHCP on eth0, and pins `net.ifnames=0` in GRUB so the NICs stay `eth0`/`eth1`. eth0 DHCP has to be baked in like this — Vagrant blocks on that lease before it can SSH in, so no provisioner can supply it.

Debug a failed build with `PACKER_LOG=1 ./build.sh -on-error=ask`.

**OVMF warning:** never point libvirt NVRAM at `/usr/share/edk2/x64/OVMF_VARS.4m.fd` — it gets clobbered. The repo vendors a template; restore the system file with `sudo cp kali/packer/ovmf/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd`.

Details: `kali/README.md` and `kali/packer/README.md`.

### Gold snapshots (all lab VMs)

After the first successful build, save a clean baseline for every machine. During testing you can wipe dirty state and restore:

```bash
./snapshot.sh take                 # snapshot "gold" in current state (provisions only if not created)
./snapshot.sh save --halt          # alias of take; halt first, then snapshot
./snapshot.sh restore              # discard current state, restore gold on all
./snapshot.sh overwrite            # overwrite gold from current state
./snapshot.sh overwrite --halt     # halt first, then overwrite gold
./snapshot.sh delete               # delete gold snapshots
./snapshot.sh list                 # check whether gold snapshots exist
```

Pass VM names to limit scope (`./snapshot.sh restore kali ws01`), and `-f` / `--force` to skip confirmations. Config (`LAB_VMS`, `SNAPSHOT_NAME`) lives at the top of `snapshot.sh`.

## Stage 2 — Sysmon everywhere

Vendored configs (not fetched live):

| Host | Agent | Config |
| ---- | ----- | ------ |
| dc, ws01 | Sysmon64 | SwiftOnSecurity → `roles/sysmon_windows/files/sysmonconfig.xml` |
| linux01 | sysmonforlinux | MSTIC-Sysmon → `roles/sysmon_linux/files/sysmonconfig.xml` |

Idempotent: install once; re-apply config only when the deployed file content changes.

```bash
cd ansible
ansible-playbook playbooks/stage2.yml
# or full stack:
ansible-playbook playbooks/site.yml
```

### Verify

```bash
cd ansible
ansible-playbook playbooks/health.yml
```

Expect: Sysmon64 running + events on Windows; `sysmon` active on linux01.

## Stage 3 — Log aggregation (ELK)

Single-node Elasticsearch + Kibana on `linux01` (8 GB). Stack pinned to **8.16.1**. Security disabled on the lab net (plain HTTP) — local only.

**Memory budget (linux01 8 GB):** ES heap **2g** · Kibana ~1g · OS + Sysmon + Filebeat ~1–2g · ~3g headroom.

| Shipper | Hosts | Source |
| ------- | ----- | ------ |
| Winlogbeat | dc, ws01 | `Microsoft-Windows-Sysmon/Operational` |
| Filebeat | linux01 | `/var/log/syslog` (sysmon lines) |

```bash
cd ansible
ansible-playbook playbooks/stage3.yml
```

### Verify

```bash
cd ansible
ansible-playbook playbooks/health.yml
xdg-open http://10.0.0.20:5601
```

Expect: ES/Kibana/Filebeat/Winlogbeat up; beat indices have Sysmon docs; Kibana data views + Discover saved searches present.

Landing opens **Discover** on **All Sysmon (lab)** (`tags : sysmon` over `filebeat-*,winlogbeat-*`). Open menu also has **Windows Sysmon** and **Linux Sysmon**.

## Lifecycle

```bash
vagrant ssh linux          # Linux only
vagrant halt
vagrant reload
vagrant destroy -f         # remove VMs only (keeps pentest-lab net)
```

### Wipe clean (full reset)

Destroys all lab VMs and the libvirt network so the next `vagrant up` recreates everything from scratch (use after subnet/password changes or a broken lab):

```bash
vagrant destroy -f
virsh -c qemu:///system net-destroy pentest-lab 2>/dev/null || true
virsh -c qemu:///system net-undefine pentest-lab 2>/dev/null || true
virsh -c qemu:///system net-list --all   # optional: find leftover 10.0.0.0/24 nets
vagrant up
cd ansible && ansible-playbook playbooks/health.yml
```

## Troubleshooting

`Network … exists but does not have dhcp disabled` — another libvirt net already owns `10.0.0.0/24`:

```bash
virsh -c qemu:///system net-list --all
virsh -c qemu:///system net-dumpxml NAME | head
virsh -c qemu:///system net-destroy NAME
virsh -c qemu:///system net-undefine NAME
vagrant up
```

`linux01` SSH `Permission denied` / `no such identity` — key path is via `inventory_dir` (see `group_vars/linux.yml`). Run Ansible from `ansible/` after `vagrant up linux`. Confirm key:

```bash
ls -l ../.vagrant/machines/linux/libvirt/private_key
ansible linux01 -m ping
```

Windows `ping` fails but `win_ping` works — apply ICMP allow (also runs on provision):

```bash
ansible domain_controllers,workstations -m ansible.builtin.include_role -a name=windows_icmp
```

## Stage 4 — Documentation site

This README is the single source for both GitHub and the Pages site. Hugo in `docs/` mounts it as the homepage and deploys on push to `main`.

```bash
# Local preview
cd docs && hugo server
# http://localhost:1313/test-net/

# Publish
git push origin main
```

One-time: repo **Settings → Pages → Source: GitHub Actions**.

### Verify

```bash
cd docs && hugo --minify && test -f public/index.html
# After push: Actions → "Deploy docs" green; open Pages URL
```
