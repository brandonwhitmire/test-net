---
title: Stage 3 — ELK
description: Elasticsearch, Kibana, Winlogbeat, Filebeat
weight: 30
---

## What it builds

- Single-node Elasticsearch + Kibana **8.16.1** on `linux01`
- Winlogbeat on dc/ws01 → Sysmon Operational
- Filebeat on linux01 → `/var/log/syslog` (sysmon lines)
- Kibana data views + Discover saved searches (`kibana_lab`)
- Security disabled (plain HTTP on lab net)

## Run

```bash
cd ansible
ansible-playbook playbooks/stage3.yml
```

## Verify

```bash
cd ansible && ansible-playbook playbooks/health.yml
xdg-open http://10.0.0.20:5601
```

Discover opens on **All Sysmon (lab)** (`tags : sysmon`). Also: **Windows Sysmon**, **Linux Sysmon**.
