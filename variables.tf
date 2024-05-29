# ---------------------------------------------------------------------------------------------------------------------
# AZURE RESOURCE VARIABLES
# Variables used for generation of Azure resources.
# ---------------------------------------------------------------------------------------------------------------------

variable "subscription_id" {
  default     = "xxxx-xxxx-xxxx-xxxx"
  description = "This is the subscription ID that Terraform will deploy the Cycle Appliance into. This subscription should be accessible by the user account that will be used during the az login."
}


variable "resource_group_name_prefix" {
  default     = "customer"
  description = "Prefix of the resource group name."
}

variable "resource_group_location" {
  default     = "eastus"
  description = "Location of the resource group."
}

variable "resource_name_prefix" {
  default     = "cycle-appliance"
  description = "Prefix of the resources that we create."
}

variable "environment_tag" {
  default     = "development"
  description = "Environment tag for the terraform deployment."
}

variable "new_vnet_address_space" {
  default     = ["10.0.0.0/22"]
  description = "CIDR range for the new virtual network that will be created."
}

variable "new_vnet_subnet_address_space" {
  default     = ["10.0.1.0/24"]
  description = "CIDR range for the new subnet that will be created within the new virtual network."
}

# ---------------------------------------------------------------------------------------------------------------------
# CLOUD INIT VARIABLES
# Variables utilized in our cloud-init script that configures the Jenkins virtual machine post-deployment.
# ---------------------------------------------------------------------------------------------------------------------

variable "jenkinsadmin" {
  default     = "cycleadmin"
  type        = string
  description = "Default Jenkins Admin user."
}

variable "jenkinspassword" {
  #default       = ""
  type        = string
  description = "Default Jenkins Admin password."
}

variable "jenkinsvmname" {
  default     = "cycle-appliance-vm"
  type        = string
  description = "Name of the VM."
}

variable "agentvmregion" {
  default     = "East US"
  type        = string
  description = "Agent Virtual Machine region."
}

variable "agentadminusername" {
  default     = "agentadmin"
  type        = string
  description = "Agent Admin username."
}

variable "agentadminpassword" {
  #default       = ""
  type        = string
  description = "Agent Admin password."
}

variable "organizationname" {
  default     = "Customer Name, Inc."
  type        = string
  description = "Customer organization."
}

variable "javahome" {
  default     = "C:\\Program Files\\Eclipse Adoptium\\jdk-11.0.16.101-hotspot"
  type        = string
  description = "Java Home"
}
