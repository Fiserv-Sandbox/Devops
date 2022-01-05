provider "azurerm" {
  version = "=2.0.0"
  features {}
}

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-test-azure-tf"
    storage_account_name = "satestzuretfrrk"
    container_name       = "terraform-state"
    key                  = "terraform.tfstate"
  }
}

resource "azurerm_resource_group" "rg-test-azure-tf" {
  name     = "rg-test-azure-tf"
  location = "northcentralus"
}
