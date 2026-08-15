# Packer — Windows lab boxes

Boxes are built from [rgl/windows-vagrant](https://github.com/rgl/windows-vagrant) (libvirt). Never Vagrant Cloud.

## Credentials (keep in sync with Ansible)

| Account | Password |
| ------- | -------- |
| `vagrant` | `vagrant` |
| `Administrator` | `AdminUser123!!!` (Ansible enforces after boot) |
| Lab users (`alice`/`bob`/`charlie`) | `LabUser123!!!` (Ansible) |

Source of truth: `lab.pkrvars.hcl` ↔ `ansible/inventory/group_vars/all.yml`

## Build + register

```bash
# In your rgl/windows-vagrant clone
make build-windows-2022-uefi-libvirt
vagrant box add -f windows-2022-uefi-amd64-libvirt windows-2022-uefi-amd64-libvirt.box

make build-windows-11-24h2-uefi-libvirt
vagrant box add -f windows-11-24h2-uefi-amd64-libvirt windows-11-24h2-uefi-amd64-libvirt.box
```

rgl defaults ship `vagrant`/`vagrant` (and Admin often matches). Lab Ansible sets Administrator → `AdminUser123!!!`.

## Optional: bake Admin password into autounattend

If you customize rgl templates, set AdministratorPassword to `AdminUser123!!!` and keep the `vagrant` user at `vagrant`. Reference values: `lab.pkrvars.hcl`.
