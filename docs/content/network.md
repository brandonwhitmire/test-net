---
title: Network
weight: 20
---

## Map

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

## Facts

- Domain: `lab.local` (alt: `lab.internal` if mDNS fights `.local`)
- Guest DNS → DC `10.0.0.10` (domain members only; kali is external)
- DHCP **disabled** on `pentest-lab` (static IPs only)
- Kali: lab reachability + internet via NAT — not domain-joined, no Sysmon/ELK
- Kibana: http://10.0.0.20:5601
- Elasticsearch: http://10.0.0.20:9200 (security off — lab net only)

## Wipe net

```bash
vagrant destroy -f
virsh -c qemu:///system net-destroy pentest-lab 2>/dev/null || true
virsh -c qemu:///system net-undefine pentest-lab 2>/dev/null || true
vagrant up
```
