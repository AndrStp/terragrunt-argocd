locals {
  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Extract out common variables for reuse
  env            = local.environment_vars.locals.environment
  azure_location = local.region_vars.locals.azure_location
}


# Terragrunt will copy the Terraform configurations specified by the source parameter, along with any files in the
# working directory, into a temporary folder, and execute your Terraform commands in that folder.

terraform {
  
  # stuck
  source = "git::https://github.com/AndrStp/learn-terraform-provision-aks-cluster.git//aks"
}


# Include all settings from the root terragrunt.hcl file

include {
  path = find_in_parent_folders()
}


# These are the variables we have to pass in to use the module specified in the terragrunt configuration above

inputs = {
  node_count      = 2
  vm_size         = "standard_b2s"
  os_disk_size_gb = 30
  location        = local.azure_location
  env             = local.env
}
