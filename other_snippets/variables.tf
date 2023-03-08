variable "datacenter_name" {
        default = "tf_test_dc__multiple_servers_with_nat_gw_and_jumpbox"
    }

    variable "location" {
        default = "de/txl"
    }

    variable "default_image" {
        default = "debian-11-genericcloud-amd64-20220328-962"
    }

    variable "default_password" {
        default = "blibbleFish19"
    }

    variable "default_ssh_key_path" {
        default = "/home/system/.ssh/id_rsa.pub"
    }


    # should probably tidy this up and turn this into a map; but for now, we
    # will assume lans[0] is the public LAN
    variable "lans" {
        default = [{
            name                    = "public"
            public                  = true
            network                 = ""
        },
        {
            name                    = "Internal LAN"
            public                  = false
            network                 = "192.168.8.0/24"
        }]
    }
