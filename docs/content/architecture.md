---
title: Architecture
weight: 10
---

## Split

| Layer | Tool | Job |
| ----- | ---- | --- |
| Lifecycle | Vagrant + libvirt/KVM | `up` / `halt` / `ssh` / `destroy` |
| Config | Ansible (host provisioner) | AD, Sysmon, ELK, shippers |
| Images | Local Packer (rgl) + `kali/` gold | Windows boxes + `kali-box` — never Vagrant Cloud for Win/Kali gold |

## Data flow (Stage 3)

```
dc / ws01  --Winlogbeat-->  Elasticsearch :9200  <--Filebeat--  linux01 (sysmon syslog)
                                      |
                                   Kibana :5601
```

## Memory (linux01 = 8 GB)

ES heap **2g** · Kibana ~1g · OS + Sysmon + Filebeat ~1–2g · ~3g headroom.

## Credentials (lab only)

| Account | Password |
| ------- | -------- |
| `vagrant` | `vagrant` |
| `Administrator` / `root` | `AdminUser123!!!` |
| `alice` / `bob` / `charlie` | `LabUser123!!!` |

Source of truth: `ansible/inventory/group_vars/all.yml` ↔ `packer/lab.pkrvars.hcl`.
