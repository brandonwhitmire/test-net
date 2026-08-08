---
title: Home
---

Local AD + Sysmon + ELK lab on libvirt/KVM. Vagrant owns VMs; Ansible configures them.

```bash
# From repo root
vagrant up
cd ansible && ansible-playbook playbooks/health.yml
```

Docs mirror the root README — keep both in sync when stages change.
