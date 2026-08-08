# Local pentest lab (libvirt / KVM)

Local AD + Sysmon + ELK lab to analyze pentesting actions via remote logging

Packer builds some custom VMs, Vagrant manages them, and Ansible configures them.

```bash
# Build and configure everything
vagrant up

# Reachability including Kali, AD/DNS/join, Sysmon, ELK + beat indices, Kibana Discover data views
cd ansible && ansible-playbook playbooks/health.yml
```

Site: https://brandonwhitmire.github.io/test-net/

### Data flow

```
dc / ws01  --Winlogbeat-->  Elasticsearch :9200  <--Filebeat--  linux01 (sysmon syslog)
                                      |
                                   Kibana :5601
```

## Network

```
                    Kali Attacker
                      10.0.0.50
                         |
              libvirt net: pentest-lab
                   10.0.0.0/24 (NAT)
           __________|__________
          |          |          |
      10.0.0.10  10.0.0.20  10.0.0.30
         dc       linux01      ws01
      AD + DNS   Ubuntu/ELK  Win11 join
```

| Host | Service | Host port → Guest |
| ---- | ------- | ----------------- |
| `dc` | SMB | 1445 → 445 |
| `dc` | WinRM | 5985 → 5985 |
| `dc` | WinRM HTTPS | 5986 → 5986 |
| `dc` | RDP | 3389 → 3389 |
| `dc` | LDAP | 1389 → 389 |
| `dc` | LDAPS | 1636 → 636 |
| `linux` | SSH | 2222 → 22 |
| `linux` | Kibana | 8888 → 5601 |
| `ws01` | SMB | 3445 → 445 |
| `ws01` | WinRM | 35985 → 5985 |
| `ws01` | WinRM HTTPS | 35986 → 5986 |
| `ws01` | RDP | 33389 → 3389 |

- Domain: `lab.local` (alt: `lab.internal`)
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
| `Administrator` / `root` | `AdminUser123!!!` | Admin users |
| `alice` / `bob` / `charlie` | `LabUser123!!!` | AD users |

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
git clone https://github.com/rgl/windows-vagrant.git

make build-windows-2022-libvirt
vagrant box add -f windows-2022-amd64 windows-2022-amd64-libvirt.box

make build-windows-11-24h2-libvirt
vagrant box add -f windows-11-24h2-amd64 windows-11-24h2-amd64-libvirt.box
```

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

**OVMF warning:** never point libvirt NVRAM at `/usr/share/edk2/x64/OVMF_VARS.4m.fd` — it gets clobbered. The repo vendors a template; restore the system file with `sudo cp kali/packer/ovmf/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd`.

## Machines

| Host (Vagrant) | Ansible | OS | IP | RAM | Role |
| -------------- | ------- | -- | -- | --- | ---- |
| `dc` | `dc` | Windows Server 2022 | 10.0.0.10 | 4 GB | AD DS + DNS (`lab.local`) |
| `linux` | `linux01` | Ubuntu 22.04 | 10.0.0.20 | 4 GB | Sysmon-for-Linux, ELK, Filebeat |
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
- Users: `alice` (LabAdmins + Domain Admins), `bob` (HelpDesk), `charlie` (Developers)


## Health check (all stages)

```bash
cd ansible
ansible-playbook playbooks/health.yml
```

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

## Sysmon everywhere

Vendored configs (not fetched live):

| Host | Agent | Config |
| ---- | ----- | ------ |
| dc, ws01 | Sysmon64 | SwiftOnSecurity → `roles/sysmon_windows/files/sysmonconfig.xml` |
| linux01 | sysmonforlinux | MSTIC-Sysmon → `roles/sysmon_linux/files/sysmonconfig.xml` |

## Log aggregation (ELK)

- Browse to Kibana: http://10.0.0.20:5601 OR http://10.0.0.20:8888

| Shipper | Hosts | Source |
| ------- | ----- | ------ |
| Winlogbeat | dc, ws01 | `Microsoft-Windows-Sysmon/Operational` |
| Filebeat | linux01 | `/var/log/syslog` (sysmon lines) |

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
