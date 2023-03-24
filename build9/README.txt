

implemented 2x 'count' on servers with for loop on a local (map)


locals {
    target_ips = compact([
        for i, server in data.ionoscloud_server.servers:
            lookup({ for nic in server.nics: nic.lan => nic.ips[0] },
                   ionoscloud_lan.lan-target.id, null)
    ])
}
target_ips (above) coderefers to (below):
    dynamic "targets" {
                for_each = {
            for ip in local.target_ips:
            ip => ip
        }    
                             ,   which returns output:     ips = tolist(["10.7.224.12", "10.7.224.11",])


RandomPen Name not implemented

Tested ssh from external Vm thourgh NLB to local IP target - success!









