

# Attributes of an _input_ variable cannot be depend on the values of resource
# attributes or other variables, however those of a _local_ variable can
locals {
    gateways = {
        jumpbox = {
            name                = "jumpbox"
            cores               = 1
            ram                 = 2048
            volumes             = [{
                name            = "hdd0"
                disk_type       = "HDD"
                disk_size       = 10
            }]
            image_name          = var.default_image
            image_password      = var.default_password
            ssh_key_path        = [ var.default_ssh_key_path ]
            user_data           = filebase64("files/cloud-init-jumpbox.txt")
            lans                = [{
                name            = "public"
                ips             = [ ionoscloud_ipblock.addresses.ips[0] ]
                dhcp            = true
                firewall_active = false
            },
            {
                name            = var.lans[1].name
                ips             = [ cidrhost(var.lans[1].network, 8) ]
                dhcp            = true
                firewall_active = false
            }]
        }
    }
}




resource "ionoscloud_datacenter" "example" {
    name                = var.datacenter_name
    location            = var.location
    description         = "Terraform Test Datacenter for ${var.datacenter_name}"
}




# address[0] is for the jumpbox, address[1] for the nat gateway
resource "ionoscloud_ipblock" "addresses" {
    location            = ionoscloud_datacenter.example.location
    name                = "IP Block for ${var.datacenter_name}"
    size                = 2
}




resource "ionoscloud_lan" "lans" {
    for_each            = { 
        for lan in var.lans:
        lan.name => lan.public
    }    

    datacenter_id       = ionoscloud_datacenter.example.id
    name                = each.key
    public              = each.value
}




# =============================================================================
# Provision the gateway server(s) and their related IP address and config files
# =============================================================================
module "provision_gateways" {
    for_each            = local.gateways

    source              = "../modules/ionoscloud_server"

    datacenter          = ionoscloud_datacenter.example
    lans                = ionoscloud_lan.lans
    server              = each.value
}


# Generate TLS keys for the jumpbox; these keys (and the public key in particu-
# lar) need to be written out to their respective files (as [ionoscloud_server]
# only accepts ssh public key _files_), however, I'm not yet sure how best to
# get the private key to the jumpbox --- possibly via Ansible?
resource "tls_private_key" "jumpbox" {
    algorithm           = "RSA"
    rsa_bits            = 4096
}


resource "local_file" "ssh_proxyjump_config" {
    filename            = "files/ssh-proxyjump.config"
    file_permission     = "0644"
    directory_permission = "0755"
    content             = <<-EOF
        Host *
          StrictHostKeyChecking accept-new
          UserKnownHostsFile files/.ssh/known_hosts

        Host jumpbox
          User root
          Hostname ${module.provision_gateways["jumpbox"].lan_id_to_ips_map[ionoscloud_lan.lans["public"].id][0]}

        Host 192.168.*
          User root
          ProxyJump jumpbox
          IdentityFile files/.ssh/id_rsa  
    EOF
}


resource "local_file" "gateway_ip_addresses" {
    for_each            = local.gateways

    filename            = "files/${each.key}/ip_address"
    file_permission     = "0644"
    directory_permission = "0755"
    content             = module.provision_gateways[each.key].lan_id_to_ips_map[ionoscloud_lan.lans["public"].id][0]
}


resource "local_file" "ssh_private_key" {
    filename            = "files/.ssh/id_rsa"
    file_permission     = "0600"
    directory_permission = "0755"
    content             = tls_private_key.jumpbox.private_key_openssh
}


resource "local_file" "ssh_public_key" {
    filename            = "files/.ssh/id_rsa.pub"
    file_permission     = "0644"
    directory_permission = "0755"
    content             = tls_private_key.jumpbox.public_key_openssh
}




# =============================================================================
# Provision and configure the NAT gateway
# =============================================================================
resource "ionoscloud_natgateway" "gateway" {
    datacenter_id       = ionoscloud_datacenter.example.id
    name                = "nat-gateway"
    public_ips          = [ ionoscloud_ipblock.addresses.ips[1] ]
    lans {
        id              = ionoscloud_lan.lans["Internal LAN"].id
        gateway_ips     = [ cidrhost(var.lans[1].network, 1) ]
    }
}


resource "ionoscloud_natgateway_rule" "snat_internal_lan" {
    datacenter_id           = ionoscloud_datacenter.example.id
    natgateway_id           = ionoscloud_natgateway.gateway.id
    name                    = "SNAT rule for Internal LAN"
    type                    = "SNAT"
    protocol                = "ALL"
    source_subnet           = var.lans[1].network
    public_ip               = ionoscloud_ipblock.addresses.ips[1]
}
