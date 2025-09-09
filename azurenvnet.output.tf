output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "private_ip_address" {
  value = azurerm_network_interface.cycleappliancenic.private_ip_address
}

output "admin_ssh_user" {
  value = azurerm_linux_virtual_machine.cycleappliancevm.admin_username
}

output "managed_identity_id" {
  value = azurerm_linux_virtual_machine.cycleappliancevm.identity[0]
}

output "jenkins_manager" {
  value = "http://${azurerm_network_interface.cycleappliancenic.private_ip_address}:8080/"
}

output "connect_now" {
  value = "ssh -i keys/${var.ssh_key_name} ${azurerm_linux_virtual_machine.cycleappliancevm.admin_username}@${azurerm_network_interface.cycleappliancenic.private_ip_address}"
}
