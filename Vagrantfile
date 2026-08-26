# frozen_string_literal: true

# Stage 1 — core network (libvirt/KVM only). Bring up DC first, then the rest.
#   vagrant up dc
#   vagrant up linux ws01
#   vagrant up kali
# Or with parallel disabled (default below): vagrant up
#
# Creds: vagrant/vagrant (guest + WinRM). Admin/root set by Ansible → AdminUser123!!!

ENV['VAGRANT_NO_PARALLEL'] = 'yes'

require 'fileutils'

LAB_NETWORK = 'pentest-lab'
DOMAIN = 'lab.local'
LAB_VAGRANT_USER = 'vagrant'
LAB_VAGRANT_PASSWORD = 'vagrant'

# Kali Packer box is UEFI-only. NVRAM must be r/w for libvirt-qemu (not under $HOME).
KALI_OVMF_CODE = '/usr/share/edk2/x64/OVMF_CODE.4m.fd'
KALI_OVMF_VARS_TEMPLATE = File.expand_path('kali/packer/ovmf/OVMF_VARS.4m.fd', __dir__)
kali_ovmf_nvram_dir = '/tmp/vagrant-kali-nvram'
kali_ovmf_vars = File.join(kali_ovmf_nvram_dir, 'kali_VARS.fd')
FileUtils.mkdir_p(kali_ovmf_nvram_dir)
File.chmod(0o777, kali_ovmf_nvram_dir)
unless File.exist?(kali_ovmf_vars)
  FileUtils.cp(KALI_OVMF_VARS_TEMPLATE, kali_ovmf_vars)
  File.chmod(0o666, kali_ovmf_vars)
end
KALI_OVMF_VARS = kali_ovmf_vars

Vagrant.configure('2') do |config|
  config.vm.synced_folder '.', '/vagrant', disabled: true

  config.vm.provider :libvirt do |lv|
    lv.driver = 'kvm'
    lv.cpu_mode = 'host-passthrough'
  end

  # --- Domain Controller (Windows Server 2022) ---
  config.vm.define 'dc', primary: true do |dc|
    dc.vm.box = 'windows-2022-uefi-amd64-libvirt'
    # Local Packer/rgl build — no version pin (not from Vagrant Cloud)
    dc.vm.hostname = 'dc'
    dc.vm.communicator = 'winrm'
    dc.winrm.username = LAB_VAGRANT_USER
    dc.winrm.password = LAB_VAGRANT_PASSWORD
    dc.winrm.transport = :plaintext
    dc.winrm.basic_auth_only = true

    dc.vm.network :private_network,
                  ip: '10.0.0.10',
                  libvirt__network_name: LAB_NETWORK,
                  libvirt__forward_mode: 'none',
                  libvirt__dhcp_enabled: false

    # Host access: AD DS / file / remote admin (no SSH on this box)
    dc.vm.network :forwarded_port, guest: 445, host: 1445, id: 'smb'
    dc.vm.network :forwarded_port, guest: 5985, host: 5985, id: 'winrm'
    dc.vm.network :forwarded_port, guest: 5986, host: 5986, id: 'winrm-https'
    dc.vm.network :forwarded_port, guest: 3389, host: 3389, id: 'rdp'
    dc.vm.network :forwarded_port, guest: 389, host: 1389, id: 'ldap'
    dc.vm.network :forwarded_port, guest: 636, host: 1636, id: 'ldaps'

    dc.vm.provider :libvirt do |lv|
      lv.memory = 4096
      lv.cpus = 2
      lv.graphics_type = 'spice'
    end

    dc.vm.provision 'ansible' do |ansible|
      ansible.playbook = 'ansible/playbooks/domain_controllers.yml'
      ansible.inventory_path = 'ansible/inventory/hosts.yml'
      ansible.limit = 'dc'
      ansible.compatibility_mode = '2.0'
      ansible.config_file = 'ansible/ansible.cfg'
    end
  end

  # --- Linux server (ELK host in later stages) ---
  config.vm.define 'linux' do |linux|
    linux.vm.box = 'generic/ubuntu2204'
    linux.vm.box_version = '4.3.12'
    linux.vm.hostname = 'linux01'

    linux.vm.network :private_network,
                     ip: '10.0.0.20',
                     libvirt__network_name: LAB_NETWORK,
                     libvirt__forward_mode: 'none',
                     libvirt__dhcp_enabled: false

    # Host access: SSH + Kibana (ELK host — no SMB/WinRM/RDP/LDAP)
    linux.vm.network :forwarded_port, guest: 22, host: 2222, id: 'ssh'
    linux.vm.network :forwarded_port, guest: 5601, host: 8888, id: 'kibana'

    linux.vm.provider :libvirt do |lv|
      lv.memory = 4096
      lv.cpus = 2
    end

    linux.vm.provision 'ansible' do |ansible|
      ansible.playbook = 'ansible/playbooks/linux.yml'
      ansible.inventory_path = 'ansible/inventory/hosts.yml'
      ansible.limit = 'linux01'
      ansible.compatibility_mode = '2.0'
      ansible.config_file = 'ansible/ansible.cfg'
    end
  end

  # --- Windows 11 workstation ---
  config.vm.define 'ws01' do |ws|
    ws.vm.box = 'windows-11-24h2-uefi-amd64-libvirt'
    ws.vm.hostname = 'ws01'
    ws.vm.communicator = 'winrm'
    ws.winrm.username = LAB_VAGRANT_USER
    ws.winrm.password = LAB_VAGRANT_PASSWORD
    ws.winrm.transport = :plaintext
    ws.winrm.basic_auth_only = true

    ws.vm.network :private_network,
                  ip: '10.0.0.30',
                  libvirt__network_name: LAB_NETWORK,
                  libvirt__forward_mode: 'none',
                  libvirt__dhcp_enabled: false

    # Host access: file / remote admin (no SSH, no LDAP — not a DC)
    ws.vm.network :forwarded_port, guest: 445, host: 3445, id: 'smb'
    ws.vm.network :forwarded_port, guest: 5985, host: 35985, id: 'winrm'
    ws.vm.network :forwarded_port, guest: 5986, host: 35986, id: 'winrm-https'
    ws.vm.network :forwarded_port, guest: 3389, host: 33389, id: 'rdp'

    ws.vm.provider :libvirt do |lv|
      lv.memory = 4096
      lv.cpus = 2
      lv.graphics_type = 'spice'
    end

    ws.vm.provision 'ansible' do |ansible|
      ansible.playbook = 'ansible/playbooks/workstations.yml'
      ansible.inventory_path = 'ansible/inventory/hosts.yml'
      ansible.limit = 'ws01'
      ansible.compatibility_mode = '2.0'
      ansible.config_file = 'ansible/ansible.cfg'
    end
  end

  # --- Kali attacker (external to domain — no AD join, no logging) ---
  # Packer UEFI gold: https://github.com/brandonwhitmire/personal-packer (kali.pkr.hcl)
  # Lab gold snapshots: ./snapshot.sh (take|save / restore / overwrite / delete)
  config.vm.define 'kali' do |kali|
    kali.vm.box = 'kali-box'
    kali.vm.hostname = 'kali'
    kali.vm.box_check_update = false

    kali.vm.network :private_network,
                    ip: '10.0.0.50',
                    libvirt__network_name: LAB_NETWORK,
                    libvirt__forward_mode: 'none',
                    libvirt__dhcp_enabled: false

    kali.vm.provider :libvirt do |lv|
      lv.memory = 4096
      lv.cpus = 2
      lv.graphics_type = 'spice'
      lv.video_type = 'qxl'
      lv.video_vram = 16_384
      # Match Packer efi_boot (see kali/packer/kali.pkr.hcl)
      lv.loader = KALI_OVMF_CODE
      lv.nvram = KALI_OVMF_VARS
    end

    # eth1 only — Ansible reaches Kali over the lab IP, which this creates.
    # eth0 (management DHCP) must come from the box; provisioners run over it.
    kali.vm.provision 'shell', name: 'lab-network',
                       path: 'kali/files/lab-network.sh',
                       run: 'always'

    kali.vm.provision 'ansible' do |ansible|
      ansible.playbook = 'ansible/playbooks/attackers.yml'
      ansible.inventory_path = 'ansible/inventory/hosts.yml'
      ansible.limit = 'kali'
      ansible.compatibility_mode = '2.0'
      ansible.config_file = 'ansible/ansible.cfg'
    end
  end
end
