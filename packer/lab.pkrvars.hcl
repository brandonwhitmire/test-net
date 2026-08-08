# Lab credentials + network for Packer builds (rgl/windows-vagrant).
# Keep in sync with ansible/inventory/group_vars/all.yml

lab_network_cidr   = "10.0.0.0/24"
lab_gateway        = "10.0.0.1"
dc_ip              = "10.0.0.10"
linux_ip           = "10.0.0.20"
ws_ip              = "10.0.0.30"

# Guest accounts baked into Windows boxes (or set post-boot by Ansible)
lab_vagrant_user     = "vagrant"
lab_vagrant_password = "vagrant"
lab_admin_password   = "AdminUser123!!!"
lab_user_password    = "LabUser123!!!"
