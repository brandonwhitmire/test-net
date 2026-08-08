---
title: Machines
weight: 30
---

| Host (Vagrant) | Ansible | OS | IP | RAM | Role |
| -------------- | ------- | -- | -- | --- | ---- |
| `dc` | `dc` | Windows Server 2022 | 10.0.0.10 | 4 GB | AD DS + DNS (`lab.local`) |
| `linux` | `linux01` | Ubuntu 22.04 | 10.0.0.20 | 8 GB | Sysmon-for-Linux, ELK, Filebeat |
| `ws01` | `ws01` | Windows 11 24H2 | 10.0.0.30 | 4 GB | Domain-joined workstation |
| `kali` | `kali` | Kali (golden `kali-box`) | 10.0.0.50 | 4 GB | External attacker — no domain, no logging |

## Boxes

| Box | Source |
| --- | ------ |
| `windows-2022-amd64` | Local Packer: `make build-windows-2022-libvirt` |
| `windows-11-24h2-amd64` | Local Packer: `make build-windows-11-24h2-libvirt` |
| `generic/ubuntu2204` `4.3.12` | Vagrant Cloud (libvirt) |
| `kali-box` | Packer UEFI ([personal-packer](https://github.com/brandonwhitmire/personal-packer/blob/main/kali.pkr.hcl)); lab gold snapshots via `./snapshot.sh` |

## Seeded AD

- OUs: `LabUsers`, `LabWorkstations`, `LabServers`, `LabGroups`
- Groups: `LabAdmins`, `HelpDesk`, `Developers`
- Users: `alice` (LabAdmins + Domain Admins), `bob` (HelpDesk), `charlie` (Developers)
