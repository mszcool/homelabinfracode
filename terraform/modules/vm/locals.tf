locals {
  # Validate that required parameters are not empty where needed
  iso_provided   = var.iso_volume_name != ""
  image_provided = var.image != ""

  # Validate that either image or iso is provided, but not both
  source_validation = {
    both_specified    = local.image_provided && local.iso_provided
    neither_specified = !local.image_provided && !local.iso_provided
  }

  # Validate pcie configuration
  pcie_required = var.enable_pcie_passthrough && var.pcie_controller == ""
  
  # Data disks should only be used when pcie passthrough is disabled
  data_disks_config = var.enable_pcie_passthrough ? [] : var.data_disks
}
