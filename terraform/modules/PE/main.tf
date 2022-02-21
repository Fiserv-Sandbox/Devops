resource "azurerm_dns_zone" "example-public" {
  name                = "mydomain.com"
  resource_group_name = azurerm_resource_group.example.name
}
resource "azurerm_private_dns_zone" "example-private" {
  name                = "mydomain.com"
  resource_group_name = azurerm_resource_group.example.name
  #Resource ID  (/subscriptions/e3bf009c-ff70-4524-a4e7-57ba50c99598/resourceGroups/non-prod-dep-platform-)
}
}
