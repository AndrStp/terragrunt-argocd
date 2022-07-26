# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.

# Azure Region names 
# https://github.com/claranet/terraform-azurerm-regions/blob/master/REGIONS.md

locals {
  azure_location = "France Central"
}
