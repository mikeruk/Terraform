2x enterprise servers
2x Random Pet Name assign

implement Random Pet Name for each server. User Count to loop over the names and assign them.

You can replace RandomPet with RandomString:
resource "random_string" "server-name" {
  count            = 2  <-- how many random you want to generate 
  length           = 2  <-- how many charachters do you want the string to have
  special          = false
}


resource "ionoscloud_server" "server_enterprise" {
  count             = 2
  name              = random_string.server-name[count.index].result  
