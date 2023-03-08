
# tried including the following in the calling 'module' clause, but this resulted in
# terraform trying to resolve hashicorp/ionoscloud instead...
terraform {
#    providers = {
#        ionoscloud = ionoscloud
#    }
    required_providers {
        ionoscloud = {
            source = "ionos-cloud/ionoscloud"
        }
    }

#    experiments = [ module_variable_optional_attrs ]
    required_version = ">= 1.3.0"
}




# We need to 'sanitise' [var.server] to make sure that: (a) if it's _actually_
# based on a snapshot, it doesn't contain any (conditionally) invalid attrib-
# utes, and (b) if it's based on an image, that the user_data attribute (if
# specified) is not 'empty'. Note that we're _not_ making sure that any user_
# data values that might be provided are valid (in this case, have a non-zero
# length)
#
# The below _used_ to be:
#
#   key => val if !contains(contains(keys(var.server), "snapshot") && var.server.snapshot != null ? ["image_password", "ssh_key_path", "user_data"] : [ ], key)
#
# however, once attributes are declared 'optional', they will always be there
# whether or not they're explicitly specified (but if they're not, they'll
# have a null value), hence the need for the if clause to be rewritten
locals {
    server_sanitised = {
        for key, val in var.server:
            key => val if !contains(var.server.snapshot != null ? ["image_password", "ssh_key_path", "user_data"] : [ ], key)
    }
}



# provision the server defined by [local.server_sanitised], using the first element of
# [local.server_sanitised.volumes] as the 'system disk'
#
# Similarly to the above, we _used_ to have the following declarations
#   image_name          = contains(keys(local.server_sanitised), "image_name") ? local.server_sanitised.image_name : contains(keys(local.server_sanitised), "snapshot") ? local.server_sanitised.snapshot : null
#   image_password      = contains(keys(local.server_sanitised), "image_name") ? lookup(local.server_sanitised, "image_password",  "") : null
#   ssh_key_path        = contains(keys(local.server_sanitised), "image_name") ? lookup(local.server_sanitised, "ssh_key_path", [ ]) : null
#       user_data       = contains(keys(local.server_sanitised), "image_name") && contains(keys(local.server_sanitised), "user_data") ? length(local.server_sanitised.user_data) > 0 ? local.server_sanitised.user_data : null : null
resource "ionoscloud_server" "server" {
    datacenter_id       = var.datacenter.id
    name                = local.server_sanitised.name
    cores               = local.server_sanitised.cores
    ram                 = local.server_sanitised.ram
    cpu_family          = var.datacenter.cpu_architecture[0].cpu_family
    image_name          = local.server_sanitised.image_name != null ? local.server_sanitised.image_name : local.server_sanitised.snapshot
    image_password      = local.server_sanitised.image_name != null ? local.server_sanitised.image_password : null
    ssh_key_path        = local.server_sanitised.image_name != null ? local.server_sanitised.ssh_key_path : null
    type                = "ENTERPRISE"
    volume {
        name            = "${local.server_sanitised.name}--${local.server_sanitised.volumes[0].name}"
        disk_type       = local.server_sanitised.volumes[0].disk_type
        size            = local.server_sanitised.volumes[0].disk_size
        user_data       = ( local.server_sanitised.image_name != null && 
                            lookup(local.server_sanitised, "user_data", null) != null && 
                            lookup(local.server_sanitised, "user_data", "") != "" ) ? lookup(local.server_sanitised, "user_data", "") : null
    }
    nic {
        lan             = var.lans[local.server_sanitised.lans[0].name].id
        name            = "${local.server_sanitised.name}--${local.server_sanitised.lans[0].name}"
        ips             = local.server_sanitised.lans[0].ips    # when ips == [ ], this forces a modify every time
        dhcp            = local.server_sanitised.lans[0].dhcp
        firewall_active = local.server_sanitised.lans[0].firewall_active
    }
}


resource "ionoscloud_volume" "secondary_volumes" {
    for_each = {
        for i, volume in slice(local.server_sanitised.volumes, 1, length(local.server_sanitised.volumes)):
            i => volume
    }

    datacenter_id       = var.datacenter.id
    server_id           = ionoscloud_server.server.id
    name                = each.value.name    # should possibly use the server name as a prefix for uniqueness' sake
    disk_type           = each.value.disk_type
    size                = each.value.disk_size
    licence_type        = "OTHER"
}


resource "ionoscloud_nic" "secondary_nics" {
    for_each = {
        for i, lan in slice(local.server_sanitised.lans, 1, length(local.server_sanitised.lans)):
            i => lan
    }

    datacenter_id       = var.datacenter.id
    server_id           = ionoscloud_server.server.id
    name                = each.value.name    # should probably use the server name as a prefix here, too
    lan                 = var.lans[each.value.name].id
    ips                 = each.value.ips
    dhcp                = each.value.dhcp
    firewall_active     = each.value.firewall_active
}




# And since [ionoscloud_server.servers[*].volume] and [...nic] only contains
# the objects that were provisioned alongside the servers, we need to query
# the ionoscloud_server _data source_ in order to get the complete list...
# Note, also, that according to https://www.terraform.io/language/data-sources#data-resource-dependencies
# the use of depends_on meta-arguments in data resources is unrecommended,
# however, I'm not sure how else to ensure that the returned object includes
# all of the volumes and nics (and as this is _only_ used in outputs.tf, I
# think this is as safe a use-case as any)
data "ionoscloud_server" "server" {
    datacenter_id       = var.datacenter.id
    id                  = ionoscloud_server.server.id

    depends_on = [
        ionoscloud_volume.secondary_volumes,
        ionoscloud_nic.secondary_nics
    ]
}


