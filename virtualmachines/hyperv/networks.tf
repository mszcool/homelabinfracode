# Hyper-V Networks Configuration

# Create lab-wan virtual switch (external switch connected to physical network)
resource "hyperv_network_switch" "lab_wan" {
  name                    = "lab-wan"
  notes                   = "External network with internet connection"
  allow_management_os     = true
  enable_embedded_teaming = false
  enable_iov              = false
  enable_packet_direct    = false
  minimum_bandwidth_mode  = "None"
  switch_type             = "External"
  net_adapter_names       = [var.external_network_adapter]
}

# Create lab-lan virtual switch (internal switch for VM communication)
resource "hyperv_network_switch" "lab_lan" {
  name                    = "lab-lan"
  notes                   = "Internal VM network"
  allow_management_os     = true
  enable_embedded_teaming = false
  enable_iov              = false
  enable_packet_direct    = false
  minimum_bandwidth_mode  = "None"
  switch_type             = "Internal"
}
