# This feature {} property is needed for Terraform; otherwise it will throw a syntax error. Silly bugs.
provider "azurerm" {
  # If you are deploying to a specific Azure subscription, put in the ID below. This subscription will need to be accessible at an admin level by the user that is used during your 'az login'
  # subscription_id = var.subscription_id
  features {}
}

# If needed, you can use this to configure Remote State. Instructions here: https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage?tabs=azure-cli
terraform {
  # Configuring remote state to an Azure storage account
  # backend "azurerm" {
  #   resource_group_name  = "tfstate"
  #   storage_account_name = "<storage_account_name>"
  #   container_name       = "tfstate"
  #   key                  = "terraform.tfstate"
  # }
}

# Setting up data for granting 'Contributor' access to the VM's System Managed Identity.
data "azurerm_subscription" "primary" {
}

# Setting up data for granting 'Contributor' access to the VM's System Managed Identity.
data "azurerm_client_config" "rg_contributor" {
}

# Running the cloud-init configuration to install Jenkins, install Jenkins plugins, apply JCasC file, etc. The variables from the deployment get injected into the cloud-init-tf.yml script and then those values are sent into various levels of the configuration: configuring Jenkins, creating a Jenkins Config-as-Code file, etc. You'll see the variables referenced in /cloud-init-tf.yml as ${jenkinsadmin}, and once Terraform runs, the value of var.jenkinsadmin, will be injected into it.
data "cloudinit_config" "server_config" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/../scripts/cloud-init-tf.yml", {
      "jenkinsadmin"       = var.jenkinsadmin
      "jenkinspassword"    = var.jenkinspassword
      "jenkinsvmname"      = var.jenkinsvmname
      "agentvmregion"      = var.agentvmregion
      "agentadminusername" = var.agentadminusername
      "agentadminpassword" = var.agentadminpassword
      "organizationname"   = var.organizationname
      "javahome"           = var.javahome
      "resourcegroupname"  = azurerm_resource_group.rg.name
      "resourcegroupid"    = azurerm_resource_group.rg.id
      "virtualnetworkname" = azurerm_virtual_network.cycleappliancenetwork.name
      "subnetname"         = azurerm_subnet.cycleappliancesubnet.name
      "nsgname"            = azurerm_network_security_group.cycleappliancensg.name
      "agentnsgname"       = azurerm_network_security_group.cycleapplianceagentnsg.name
      "jenkinsserverport"  = "http://${azurerm_network_interface.cycleappliancenic.private_ip_address}:8080/"
      "jenkinsserver"      = azurerm_network_interface.cycleappliancenic.private_ip_address
    })
  }
}

# Creating the Azure Resource Group.
resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name_prefix}-cycappl"
  location = var.resource_group_location
  tags = {
    environment = var.environment_tag
  }
}

# Create Recovery Services vault.
resource "azurerm_recovery_services_vault" "cycleappliancevault" {
  name                = "${var.resource_name_prefix}-vault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  # This should get changed back to true when this gets ready for prodcution. It's just a admin nightmare to have to disable softdeletion when I am doing so much testing
  soft_delete_enabled = false
  tags = {
    environment = var.environment_tag
  }
}

# Creating Default Backup Policy.
resource "azurerm_backup_policy_vm" "defaultpolicy" {
  name                = "${var.resource_name_prefix}-vaultpolicy"
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.cycleappliancevault.name
  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 7
  }

  retention_weekly {
    count    = 8
    weekdays = ["Sunday", "Wednesday"]
  }
}



# Create public IP address
### FOR DEVELOPMENT/TESTING PURPOSES ONLY ###
# This should NEVER be used in a production environment, as the Cycle Appliance should be only accessible via private routing.
# Uncomment if you want a public IP address to be associated with the Cycle Appliance virtual machine.
resource "azurerm_public_ip" "cycleappliancepip" {
  name                = "${var.resource_name_prefix}-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
}

# Create virtual network.
resource "azurerm_virtual_network" "cycleappliancenetwork" {
  name                = "${var.resource_name_prefix}-vnet"
  address_space       = var.new_vnet_address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags = {
    environment = var.environment_tag
  }
}

# Create subnet.
resource "azurerm_subnet" "cycleappliancesubnet" {
  name                 = "${var.resource_name_prefix}-snet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.cycleappliancenetwork.name
  address_prefixes     = var.new_vnet_subnet_address_space
}

# Create Network Security Group and rules for the Jenkins Manager.
# This NSG gets assigned the default rules - which allows communication between the VNet - that is why no rules are specified.
resource "azurerm_network_security_group" "cycleappliancensg" {
  name                = "${var.resource_name_prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags = {
    environment = var.environment_tag
  }

  ### FOR DEVELOPMENT/TESTING PURPOSES ONLY ###
  # This should NEVER be used in a production environment, as the Cycle Appliance should be only accessible via private routing.
  # Uncomment if you want a network security group to allow port 22 to be open to the internet, so that you can SSH into the Cycle Appliance VM via the public IP address.

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-jenkins-8080"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Adding a Network Security Group for agent VM's.
# This NSG gets assigned the default rules - which allows communication between the VNet - that is why no rules are specified.
resource "azurerm_network_security_group" "cycleapplianceagentnsg" {
  name                = "${var.resource_name_prefix}-agent-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags = {
    environment = var.environment_tag
  }
}

# Create network interface for Jenkins Manager.
resource "azurerm_network_interface" "cycleappliancenic" {
  name                = "${var.resource_name_prefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags = {
    environment = var.environment_tag
  }

  ip_configuration {
    name                          = "${var.resource_name_prefix}-nic-config"
    subnet_id                     = azurerm_subnet.cycleappliancesubnet.id
    private_ip_address_allocation = "Dynamic"
    ### FOR DEVELOPMENT/TESTING PURPOSES ONLY ###
    # This should NEVER be used in a production environment, as the Cycle Appliance should be only accessible via private routing.
    # Uncomment out public_ip_address_id here if you are wanting this environment to be accessible via a public IP address.
    public_ip_address_id = azurerm_public_ip.cycleappliancepip.id
  }
}

# Connect the security group to the network interface.
resource "azurerm_network_interface_security_group_association" "nsgassociation" {
  network_interface_id      = azurerm_network_interface.cycleappliancenic.id
  network_security_group_id = azurerm_network_security_group.cycleappliancensg.id
}

# Generate random text for a unique storage account name.
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

# Create storage account for boot diagnostics.
resource "azurerm_storage_account" "mystorageaccount" {
  name                     = "diag${random_id.randomId.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags = {
    environment = var.environment_tag
  }
}

# Create the Jenkins Manager virtual machine.
resource "azurerm_linux_virtual_machine" "cycleappliancevm" {
  name                = "${var.resource_name_prefix}-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags = {
    environment = var.environment_tag
  }
  depends_on = [
    azurerm_network_interface_security_group_association.nsgassociation
  ]
  network_interface_ids = [azurerm_network_interface.cycleappliancenic.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "${var.resource_name_prefix}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Pull latest Ubuntu 22.04 LTS version.
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # Creating Managed Identity for the Jenkins Manager.
  identity {
    type = "SystemAssigned"
  }

  computer_name                   = var.jenkinsvmname
  admin_username                  = var.jenkinsadmin
  disable_password_authentication = true
  custom_data                     = data.cloudinit_config.server_config.rendered

  # You will need to use ssh-keygen to create an SSH keypair; you will then want to move the public key into the /keys/ folder and update line #243 with the appropriate filename.
  admin_ssh_key {
    username = var.jenkinsadmin
    # Referencing a key file stored in the repository
    public_key = file("./keys/cycleappliance.pub")
  }

  # Creating boot diagnostics for the Jenkins Manager VM.
  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
  }
}

# Enrolling Jenkins Manager VM into backup policy.
resource "azurerm_backup_protected_vm" "cycleappliancevm" {
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.cycleappliancevault.name
  source_vm_id        = azurerm_linux_virtual_machine.cycleappliancevm.id
  backup_policy_id    = azurerm_backup_policy_vm.defaultpolicy.id
}

# Assigning the Contributor role to the newly created System Managed Identity. This will allow Jenkins Azure VM Agent plugin to communicate with the Azure tenant within this resource group. This allows VM's to be spun up/deleted.
resource "azurerm_role_assignment" "example" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_virtual_machine.cycleappliancevm.identity[0].principal_id
  depends_on = [
    azurerm_linux_virtual_machine.cycleappliancevm
  ]
}
