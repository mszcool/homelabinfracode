# Incus Networks Configuration

# Create lab-wan network (bridged to host network for internet access)
resource "incus_network" "lab_wan" {
  name = "lab-wan"
  
  config = {
    "ipv4.address" = "192.168.1.1/24"
    "ipv4.nat"     = "true"
    "ipv6.address" = "none"
  }
}

# Create lab-lan network (internal network)
resource "incus_network" "lab_lan" {
  name = "lab-lan"
  
  config = {
    "ipv4.address" = var.lab_lan_subnet
    "ipv4.nat"     = "false"
    "ipv6.address" = "none"
    "dns.domain"   = var.lab_lan_domain
  }
}
