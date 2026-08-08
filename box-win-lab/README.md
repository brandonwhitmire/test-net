# Windows FLARE VM Lab

An automated Windows lab environment with FLARE VM provisioned using Ansible and managed via Vagrant.
The provisioning is handled by the `flare-vm` Ansible role located in `roles/flare-vm/`.
NOTE: FLARE VM installation can take a significant amount of time (120+ minutes)

- [FLARE VM Installation Documentation](https://github.com/mandiant/flare-vm?tab=readme-ov-file#flare-vm-installation)

## Setup

1. **Build base box** (if needed)

   If you don't already have the `windows-2022-amd64` Vagrant box, you can build it using the provided script:

   ```bash
   ./build-packer2vagrant-windows-2022_x64.sh
   ```

   **Note:** Building the base box requires Packer and can take 120+ minutes depending on your system

2. **Install dependencies:**

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip3 install -r requirements.txt
   ansible-galaxy collection install -r requirements.yml
   ```

3. **Provision the VM:**

   ```bash
   source .venv/bin/activate && vagrant up
   ```
