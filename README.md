# Local pentest lab (libvirt / KVM)

Vagrant manages VMs. Ansible configures them. Stages 1–4 complete.

## Assumptions

- Provider: **libvirt + QEMU/KVM** (no VirtualBox).
- Domain: `lab.local` (alt: `lab.internal` if mDNS fights `.local`).
- Ubuntu box: `generic/ubuntu2204` **4.3.12**.
- Windows boxes: local Packer builds from [rgl/windows-vagrant](https://github.com/rgl/windows-vagrant) — never Vagrant Cloud.
- Kali attacker: local golden box `kali-box` (factory + scripts in `kali/`) — not domain-joined, not logged.
- Private net `pentest-lab` `10.0.0.0/24`, NAT outbound so guests can update.

## Credentials

| Account | Password | Where |
| ------- | -------- | ----- |
| `vagrant` | `vagrant` | WinRM / SSH / Vagrant |
| `Administrator` / `root` | `AdminUser123!!!` | Ansible after provision |
| `alice` / `bob` / `charlie` | `LabUser123!!!` | AD (Ansible) |

Vars: `ansible/inventory/group_vars/all.yml` and `packer/lab.pkrvars.hcl` (keep synced).

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

| Host    | Role        | IP         | RAM  | vCPU |
| ------- | ----------- | ---------- | ---- | ---- |
| dc      | AD DS + DNS | 10.0.0.10  | 4 GB | 2    |
| linux   | Ubuntu 22.04 (`linux01` in Ansible) | 10.0.0.20 | 8 GB | 2 |
| ws01    | Win11 join  | 10.0.0.30  | 4 GB | 2    |
| kali    | Attacker (no domain / no logging) | 10.0.0.50 | 4 GB | 2 |

## Layout

```
Vagrantfile
kali/                          # Attacker: Packer (UEFI kali-box), snapshots, network bootstrap
docs/                          # Hugo site → GitHub Pages
.github/workflows/docs.yml
packer/{README.md,lab.pkrvars.hcl}   # Windows boxes (rgl)
ansible/
  ansible.cfg
  requirements.yml
  inventory/hosts.yml
  inventory/group_vars/{all,domain_controllers,linux,workstations}.yml
  playbooks/{site,stage2,stage3,domain_controllers,linux,workstations,health}.yml
  roles/{ad_forest,ad_objects,domain_join,linux_base,windows_admin_password,windows_icmp,
         sysmon_windows,sysmon_linux,elk,winlogbeat,filebeat_sysmon,kibana_lab}/
```

## Health check (all stages)

```bash
cd ansible
ansible-playbook playbooks/health.yml
```

Covers Stages 1–3 (reachability including Kali, AD/DNS/join, Sysmon, ELK + beat indices, Kibana Discover data views).

## Stage 1 — Core network

Promotes `dc` to AD DS (`lab.local`), seeds OUs/users/groups, joins `ws01`, points `linux` DNS at the DC.

```bash
# Bring up (serial: DC first — VAGRANT_NO_PARALLEL is set in Vagrantfile)
vagrant up

# Or stepwise
vagrant up dc
vagrant up linux
vagrant up ws01
vagrant up kali    # attacker on 10.0.0.50 — provisioned by playbooks/attackers.yml
```

Re-run Ansible only:

```bash
cd ansible
ansible-playbook playbooks/site.yml
# or per group:
ansible-playbook playbooks/domain_controllers.yml
ansible-playbook playbooks/linux.yml
ansible-playbook playbooks/workstations.yml
```

### Verify

```bash
cd ansible
ansible-playbook playbooks/health.yml
```

Expect: all plays green (ICMP, WinRM/SSH, DNS, users/groups, domain join).

### Seeded AD objects

- OUs: `LabUsers`, `LabWorkstations`, `LabServers`, `LabGroups`
- Groups: `LabAdmins`, `HelpDesk`, `Developers`
- Users: `alice` (LabAdmins + Domain Admins), `bob` (HelpDesk), `charlie` (Developers) — password `LabUser123!!!`

### Kali attacker

External to the domain (no join, no Sysmon/ELK). Same `pentest-lab` NAT net at **10.0.0.50**.

Box: local golden **`kali-box`** (UEFI/GPT — Vagrantfile boots it with OVMF).

```bash
vagrant up kali && vagrant ssh kali
# or: ./kali/0_run_attacker_box.sh
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
vagrant destroy -f kali        # drop any old VM built from the previous box
vagrant up kali
```

The preseed enables SSH, passwordless sudo, `qemu-guest-agent`, DHCP on eth0, and pins `net.ifnames=0` in GRUB so the NICs stay `eth0`/`eth1`. eth0 DHCP has to be baked in like this — Vagrant blocks on that lease before it can SSH in, so no provisioner can supply it.

Debug a failed build with `PACKER_LOG=1 ./build.sh -on-error=ask`.

**OVMF warning:** never point libvirt NVRAM at `/usr/share/edk2/x64/OVMF_VARS.4m.fd` — it gets clobbered. The repo vendors a template; restore the system file with `sudo cp kali/packer/ovmf/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd`.

Details and the snapshot-based gold-image factory: `kali/README.md` and `kali/packer/README.md`.

## Stage 2 — Sysmon everywhere

Vendored configs (not fetched live):

- Windows: SwiftOnSecurity `sysmonconfig-export.xml` → `roles/sysmon_windows/files/sysmonconfig.xml`
- Linux: MSTIC-Sysmon `linux/configs/main.xml` → `roles/sysmon_linux/files/sysmonconfig.xml`

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

Expect: Sysmon64 running + events on Windows; `sysmon` active on linux01 (covered by health.yml).

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
```

Expect: ES/Kibana/Filebeat/Winlogbeat up; beat indices have Sysmon docs; Kibana data views + Discover saved searches present.

#### Browser

```bash
xdg-open http://10.0.0.20:5601
```

Landing opens **Discover** on **All Sysmon (lab)** (`tags : sysmon` over `filebeat-*,winlogbeat-*`). Open menu also has **Windows Sysmon** and **Linux Sysmon**.

**Kibana URL:** http://10.0.0.20:5601

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
# From repo root
vagrant destroy -f

# Drop the lab network (ignore errors if already gone)
virsh -c qemu:///system net-destroy pentest-lab 2>/dev/null || true
virsh -c qemu:///system net-undefine pentest-lab 2>/dev/null || true

# Optional: remove leftover conflicting nets on 10.0.0.0/24
virsh -c qemu:///system net-list --all

# Bring the lab back up
vagrant up
cd ansible && ansible-playbook playbooks/health.yml
```

## Troubleshooting

`Network … exists but does not have dhcp disabled` — another libvirt net already owns `10.0.0.0/24`:

```bash
virsh -c qemu:///system net-list --all
virsh -c qemu:///system net-dumpxml NAME | head   # find the conflict
virsh -c qemu:///system net-destroy NAME          # if active
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

Hugo site in `docs/` (architecture, network map, machines, stages). CI deploys to GitHub Pages on push to `main`.

```bash
# Local preview
cd docs && hugo server
# http://localhost:1313/test-net/

# Publish
git push origin main
```

One-time: repo **Settings → Pages → Source: GitHub Actions**.

**Site:** https://brandonwhitmire.github.io/test-net/

### Verify

```bash
cd docs && hugo --minify && test -f public/index.html
# After push: Actions → "Deploy docs" green; open Pages URL
```
