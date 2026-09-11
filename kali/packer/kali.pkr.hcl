packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

locals {
  kali_box_name      = "kali-box"
  kali_box_version   = "1.0"
  kali_box_provider  = "libvirt"
  kali_output_dir    = "output-kali"
  kali_disk_size_gib = 40
}

variable "kali_iso_url" {
  type = string
}

variable "kali_iso_checksum" {
  type = string
}

source "qemu" "kali" {
  cpus                 = 2
  #memory               = 4096
  memory               = 8192
  disk_size            = local.kali_disk_size_gib * 1024
  #headless             = true
  headless             = false
  iso_url              = var.kali_iso_url
  iso_checksum         = var.kali_iso_checksum
  http_directory       = "."
  efi_boot             = true
  efi_firmware_code    = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
  efi_firmware_vars    = "${path.root}/ovmf/OVMF_VARS.4m.fd"
  boot_command = [
    "c",
    "<wait2s>",
    "linux /install.amd/vmlinuz net.ifnames=0 auto=true priority=critical preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/resources/kali-preseed.cfg DEBIAN_FRONTEND=text",
    "<enter>",
    "initrd /install.amd/initrd.gz",
    "<enter>",
    "boot",
    "<enter>"
  ]
  boot_wait         = "10s"
  boot_key_interval = "50ms"
  shutdown_command  = "echo 'vagrant' | sudo --stdin shutdown --poweroff now"
  shutdown_timeout  = "10m"
  communicator      = "ssh"
  ssh_username      = "vagrant"
  ssh_password      = "vagrant"
  # A `standard` Kali install pulls a lot over the network — 30m is too tight on
  # a slow mirror and shows up as a bogus "Timeout waiting for SSH".
  ssh_timeout       = "60m"
  vm_name           = "box"
  output_directory  = local.kali_output_dir
  format            = "qcow2"
}

build {
  sources = ["source.qemu.kali"]

  provisioner "shell" {
    inline = [
      "mkdir -p /home/vagrant/.ssh",
      "chown -R vagrant:vagrant /home/vagrant/.ssh",
      "curl -fsSL https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub -o /home/vagrant/.ssh/authorized_keys",
      "chmod 700 /home/vagrant/.ssh",
      "chmod 600 /home/vagrant/.ssh/authorized_keys",
      "echo 'vagrant ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/10-vagrant",
      "sudo chmod 0440 /etc/sudoers.d/10-vagrant",
      "sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config",
      "sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo systemctl restart sshd"
    ]
  }

  post-processor "vagrant" {
    output              = "${local.kali_output_dir}/${local.kali_box_name}-${local.kali_box_provider}-${local.kali_box_version}.box"
    architecture        = "amd64"
    compression_level   = 6
    keep_input_artifact = true
  }
}
