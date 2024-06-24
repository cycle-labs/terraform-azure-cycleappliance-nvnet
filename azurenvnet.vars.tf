# ---------------------------------------------------------------------------------------------------------------------
# DATA FETCHING VARIABLES
# Variables used for fetching data from Azure.
# ---------------------------------------------------------------------------------------------------------------------

variable "subscription_id" {
  description = "This is the subscription ID that Terraform will deploy the Cycle Appliance into. This subscription should be accessible by the user account that will be used during the az login."
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# AZURE RESOURCE VARIABLES
# Variables used for generation of Azure resources.
# ---------------------------------------------------------------------------------------------------------------------

variable "resource_group_location" {
  description = "Location of the resource group. Some examples are: eastus, eastus2, westus, centralus"
  type        = string
}

variable "resource_name_prefix" {
  default     = "cycleappliance"
  description = "Prefix of the resources that we create."
  type        = string
}

variable "env_tag" {
  description = "Environment tag for the terraform deployment."
  type        = string
}

variable "owner_tag" {
  description = "The person who created the resource."
  type        = string
}

variable "os_type" {
  default = "ubuntu"
  description = "The operating system type for the Jenkins manager virtual machine. For ubuntu, we deploy the latest release of Ubuntu 22.04. For redhat, we deploy the latest release of RHEL 9.4. Possible values: ubuntu, redhat"
  type = string
}

variable "jenkins_mgr_sku" {
  default     = "Standard_D2_v4"
  description = "The VM SKU for the Jenkins Manager. We recommend a minimum instance SKU of Standard_DS1_v2, but if you want to increase the SKU you can do so. NOTE: We decided to use Azure VM SKU's without temporary disks attached, as we do not leverage these at all for the Jenkins Manager."
  type        = string
}

variable "ssh_key_name" {
  description = "Name of the SSH keypair file(s) within the /keys/ directory that you created using ssh-keygen. We will append the .pub and .pem."
  type        = string
}

variable "vnet_address_space" {
  description = "CIDR range for the new virtual network that will be created."
  type        = list(any)
}

variable "subnet_address_space" {
  description = "CIDR range for the new subnet that will be created within the new virtual network"
  type        = list(any)
}

variable "backup_frequency" {
  description = "The frequency of the backup."
  type        = string
  default     = "Daily"
}

variable "backup_time" {
  description = "The time at which the backup is taken."
  type        = string
  default     = "23:00"
}

variable "retention_daily_count" {
  description = "The number of daily retention points."
  type        = number
  default     = 7
}

variable "retention_weekly_count" {
  description = "The number of weekly retention points."
  type        = number
  default     = 8
}

variable "retention_weekly_days" {
  description = "The days of the week for weekly retention."
  type        = list(string)
  default     = ["Sunday", "Wednesday"]
}

variable "os_type" {
  description = "The type of operating system to be used for the Jenkins manager (e.g., 'ubuntu' or 'redhat')"
  type        = string
}

#This locals block combines both the env_tag and owner_tag together. Feel free to add more variables for tags, add 
#those tags to the locals block (using owner and environment below as examples), and they'll be merged into all resources created with this code.
locals {
  std_tags = {
    owner       = var.owner_tag
    environment = var.env_tag
  }
  os_map = {
    "ubuntu" = {
      publisher       = "Canonical"
      offer           = "0001-com-ubuntu-server-jammy"
      sku             = "22_04-lts"
      cloud_init_file = "${path.module}/../scripts/cloud-init-tf.yml"
    }
    "redhat" = {
      publisher       = "RedHat"
      offer           = "RHEL"
      sku             = "94_gen2"
      cloud_init_file = "${path.module}/../scripts/rhel-cloud-init-tf.yml"
    }
  }
  selected_os = local.os_map[var.os_type]

}

# ---------------------------------------------------------------------------------------------------------------------
# CLOUD INIT VARIABLES
# Variables utilized in our cloud-init script that configures the Jenkins virtual machine post-deployment.
# ---------------------------------------------------------------------------------------------------------------------

variable "jenkinsadmin" {
  description = "Default Jenkins Admin user."
  type        = string
}

variable "jenkinspassword" {
  description = "Default Jenkins Admin password."
  type        = string
}

variable "agentadminusername" {
  default     = "administrator"
  description = "Agent Admin username"
  type        = string
}

variable "agentadminpassword" {
  default     = "68q79h4W#mN4k87P#!JQ"
  description = "Agent Admin password"
  type        = string
}
