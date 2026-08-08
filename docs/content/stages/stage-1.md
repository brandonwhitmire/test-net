---
title: Stage 1 — Core network
description: AD forest, DNS, domain join
weight: 10
---

## What it builds

- Promotes `dc` to AD DS (`lab.local`) + DNS
- Seeds OUs / groups / users
- Joins `ws01` to the domain
- Points `linux01` DNS at the DC
- Brings up `kali` on `10.0.0.50` (external attacker — no domain join, no logging)

## Bring up

```bash
vagrant up
# or: vagrant up dc && vagrant up linux && vagrant up ws01 && vagrant up kali
```

Re-run Ansible only:

```bash
cd ansible
ansible-playbook playbooks/domain_controllers.yml
ansible-playbook playbooks/linux.yml
ansible-playbook playbooks/workstations.yml
```

## Verify

```bash
cd ansible && ansible-playbook playbooks/health.yml
```
