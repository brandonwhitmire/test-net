---
title: Stage 2 — Sysmon
description: Vendored Sysmon on all hosts
weight: 20
---

## What it builds

| Host | Agent | Config |
| ---- | ----- | ------ |
| dc, ws01 | Sysmon64 | SwiftOnSecurity (vendored) |
| linux01 | sysmonforlinux | MSTIC-Sysmon Linux (vendored) |

Idempotent: install once; re-apply config only when file content changes.

## Run

```bash
cd ansible
ansible-playbook playbooks/stage2.yml
```

## Verify

```bash
cd ansible && ansible-playbook playbooks/health.yml
```
