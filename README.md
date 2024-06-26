# Cycle Appliance 
[[_TOC_]]

# Cycle Appliance Overview

The Cycle Appliance consolidates all the essential cloud infrastructure required to seamlessly execute Cycle tests autonomously. Instead of grappling with the complexities of setting up Cycle on a local machine or manually configuring cloud resources for Jenkins management and testing agents, the Cycle Appliance furnishes pre-configured infrastructure tailored for running Cycle tests in your cloud environment. Its primary objective is to streamline the setup process, significantly reducing the time required for customers to establish the necessary testing infrastructure and enabling prompt initiation of Cycle tests. It's worth noting that Cycle provides optimal value when employed within a CI/CD mindset, and the Cycle Appliance is designed to deliver this seamlessly out of the box.

Leveraging Terraform, the Cycle Appliance automates the setup and configuration of cloud infrastructure. By utilizing Terraform as an infrastructure-as-code language, it provisions and configures resources within the selected cloud provider. Given the slight variations in offerings among cloud providers, our Terraform code is meticulously adapted to meet the specific requirements for executing Cycle tests. Our overarching goal is to ensure consistency in deployment across all supported cloud providers, thereby enhancing interoperability and user experience.


#### Key Features

- Utilizes [Terraform](https://www.terraform.io/), an open-source infrastructure-as-code language developed by HashiCorp.
- Automated deployment of required infrastructure for autonomous Cycle testing in Microsoft Azure or Amazon AWS cloud environments.
- Automated configuration of the [Jenkins](https://jenkins.io) environment to allow it to integrate with the public cloud provider for dynamically provisioning testing agents.
- Customized Terraform code tailored to each cloud provider's specifications, ensuring optimal resource utilization.


### What Cycle Appliance for Azure builds
***

The architecture diagram for the Cycle Appliance is below; these resources are built and configured with the Terraform code.

- ![Image](https://cycldocimgs.blob.core.windows.net/docimgs/azure-architecture.png)

### Jenkins Manager Operating System
***

We acknowledge that some of our customers may have Linux distribution requirements, so we have built in the ability to use Ubuntu or Red Hat Enterprise Linux (RHEL) to the Cycle Apppliance and to have the deployment dynamically adjust what is deployed and configured based on the operating system type. This is controlled by the `os_type` variable that accepts the two following values: `ubuntu` or `redhat`. 

Some high level notes 
- When toggling between the different operating systems with the `os_type` variable, we dynamically send in values to properly deploy the proper Linux distribution, and to also run the required `cloud-init` script to support that distribution.
  - Just for a bit more understanding: `selected_os` is the combination of the `os_map` map, the `os_type` variable and is used to dynamically set the configurations for the virtual machine based on the selected operating system. The code for this (`azureevnet.vars.tf`, `azurenvnet.vars.tf`) can be viewed below.

```
variable "os_type" {
  description = "The type of operating system to be used for the Jenkins manager (e.g., 'ubuntu' or 'redhat')"
  type        = string
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

  selected_os = local.os_map[var.os_type]

```

- Be aware that RHEL does cost more money hourly than Ubuntu, as it is not an open source Linux distribution. More info can be found [here.](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/redhat.rhel-20190605?tab=Overvie)
- The package manager we use for Ubuntu is `apt`
- The package manager we use for RHEL is `yum`

### Managed Identity
***

The Cycle Appliance has the ability to dynamically spin up and spin down testing agents from virtual machines. This is achieved by the use of an (Azure Managed Identity)[https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview] that is created and assigned to the Jenkins Manager virtual machine. This Managed Identity is enabled on the Virtual Machine, and given `Contributor` role on the resource group that is used for deploying the Cycle Appliance into.

#### Key Features
- This allows the Jenkins manager to dynamically build testing agents using the [Azure VM Agent](https://plugins.jenkins.io/azure-vm-agents/) Jenkins plugin. This is a plugin built by Microsoft to enable people to leverage their cloud for testing agents and only pay for them while they're online.
- Managed Identity can be assigned required RBAC roles to access any other required cloud resources.
- Managed Identity has no administrative burden; no secret rotation or expiration. This is all managed by Azure.

### Cloud Initialization script
***

The `cloud-init` script (`cloud-init-tf.yml`) is where all of the host-based configuration happens. We use this scripting language to configure the Jenkins Manager virtual machine, after it has been deployed into the cloud. This `cloud-init` script gets generated by Terraform, encoded as `base64`, with all of the variables injected into it, and then passes it into the virtual machine as it's deployed via the `custom_data` property. This way, right after the cloud provider builds the virtual machine resource, it executes the `cloud-init` script and configures that virtual machine to its desired state.

#### Key Features
- Updates all packages to ensure the Linux virtual machine is up to date with latest packages.
- Configures Jenkins fully with a Jenkins Configuration as Code file (jenkins.yaml)
- Installs required Jenkins plugins.
- Connects Jenkins into the Azure Resource Group with the Managed Identity, giving it `Contributor` level access. This is for programatic VM creation with the Azure VM Agent plugin.
- Configure an initialization script for new Azure VM Agents to connect via JNLP. This script is created inside of Jenkins as a Cloud Template, and ran when new agents are deployed by Jenkins. This allows the agents to be spun up in the cloud provider, configured, and then checked into Jenkins as testing agents.
- A LOT of variables are sent into this `cloud-init` from the Terraform deployment itself (see below), as well as dynamically retrieved resource ID's from the Azure ARM API. This is the beauty of Terraform, we can easily interpolate all of this data and put it in place in our script files to allow for a way better configuration-as-code. 

```
    data "cloudinit_config" "server_config" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = templatefile(local.selected_os.cloud_init_file, {
      "jenkinsadmin"                  = var.jenkinsadmin
      "jenkinspassword"               = var.jenkinspassword
      "jenkinsvmname"                 = var.jenkinsvmname
      "agentvmregion"                 = var.agentvmregion
      "agentadminusername"            = var.agentadminusername
      "agentadminpassword"            = var.agentadminpassword
      "organizationname"              = var.organizationname
      "javahome"                      = var.javahome
      "resourcegroupname"             = azurerm_resource_group.rg.name
      "resourcegroupid"               = azurerm_resource_group.rg.id
      "virtualnetworkname"            = data.azurerm_subnet.dev_vnet_subnet.virtual_network_name
      "subnetname"                    = data.azurerm_subnet.dev_vnet_subnet.name
      "existingvnetresourcegroupname" = data.azurerm_subnet.dev_vnet_subnet.resource_group_name
      "nsgname"                       = azurerm_network_security_group.cycleappliancensg.name
      "agentnsgname"                  = azurerm_network_security_group.cycleapplianceagentnsg.name
      "jenkinsserverport"             = "http://${azurerm_network_interface.cycleappliancenic.private_ip_address}:8080/"
      "jenkinsserver"                 = azurerm_network_interface.cycleappliancenic.private_ip_address
    })
  }
}
```

## Preparing for Deployment
***
Our Terraform code is broken out into two different deployment types: `new-vnet` and `existing-vnet`. `new-vnet` is if you want a new Azure virtual network to be deployed and used for your Cycle Appliance. `existing-vnet` is if you want to deploy the Cycle Appliance to an existing virtual network and subnet. The necessary Terraform files for each of these two deployment types are under the appropriate subfolder. You should determine witch deployment you want to use, and move work within that directory. 

### Installing Terraform
***

***Please note that if you are using Terraform Cloud, you should just simply clone the repistory and store it on a source code tool that your Terraform Cloud is connected to. You can skip the below steps.***
If you are doing the Terraform deployment locally, the Terraform binary will need to be installed from wherever the deployment will take place. 

- Make sure you have Terraform installed locally, and that `terraform` is in your `PATH`.
    - [HashiCorp Documentation on installing Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) - they explain it better than we can.

### Authenticate to Azure
***

You will need to authenticate to Azure with a user that has administrative privledges to the subscription you plan to deploy the Cycle Appliance into. 

- [HashiCorp Documentation on authentication to Azure](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli) - we use `az login` to authenticate to our Azure tenant, but there are many options. 

Below is Microsoft's documentation on authenticating to Azure via either `az login` or with the use of a **Service Principal**. There was no reason for us to reinvent the wheel by rewriting their documentation, so it exists as Microsoft has written it below. If you want to read the documentation directly, you can do that [here.](https://learn.microsoft.com/en-us/azure/developer/terraform/authenticate-to-azure?tabs=bash)


#### Terraform and Azure authentication scenarios

Terraform only supports authenticating to Azure via the Azure CLI. Authenticating using Azure PowerShell isn't supported. Therefore, while you can use the Azure PowerShell module when doing your Terraform work, you first need to authenticate to Azure using the Azure CLI.

This article explains how to authenticate Terraform to Azure for the following scenarios. For more information about options to authenticate Terraform to Azure, see [Authenticating using the Azure CLI](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/guides/azure_cli).

- [Authenticate via a Microsoft account using Cloud Shell (with Bash or PowerShell)](#authenticate-to-azure-via-a-microsoft-account)
- [Authenticate via a Microsoft account using Windows (with Bash or PowerShell)](#authenticate-to-azure-via-a-microsoft-account)
- Authenticate via a service principal:
    1. If you don't have a service principal, [create a service principal](#create-a-service-principal).
    1. [Authenticate to Azure using environment variables](#specify-service-principal-credentials-in-environment-variables) or [authenticate to Azure using the Terraform provider block](#specify-service-principal-credentials-in-a-terraform-provider-block)

#### Authenticate to Azure via a Microsoft account

A Microsoft account is a username (associated with an email and its credentials) that is used to sign in to Microsoft services - such as Azure. A Microsoft account can be associated with one or more Azure subscriptions, with one of those subscriptions being the default.

The following steps show you how:

- Sign in to Azure interactively using a Microsoft account
- List the account's associated Azure subscriptions (including the default)
- Set the current subscription.

1. Open a command line that has access to the Azure CLI.

1. Run `az login` without any parameters and follow the instructions to sign in to Azure.

    ```azurecli
    az login
    ```

    **Key points:**

    - Upon successful sign in, `az login` displays a list of the Azure subscriptions associated with the logged-in Microsoft account, including the default subscription.

1. To confirm the current Azure subscription, run `az account show`.

    ```azurecli
    az account show
    ```

1. To view all the Azure subscription names and IDs for a specific Microsoft account, run `az account list`. 

    ```azurecli
    az account list --query "[?user.name=='<microsoft_account_email>'].{Name:name, ID:id, Default:isDefault}" --output Table
    ```

    **Key points:**

    - Replace the `<microsoft_account_email>` placeholder with the Microsoft account email address whose Azure subscriptions you want to list.
    - With a Live account - such as a Hotmail or Outlook - you might need to specify the fully qualified email address. For example, if your email address is `admin@hotmail.com`, you might need to replace the placeholder with `live.com#admin@hotmail.com`.

1.  To use a specific Azure subscription, run `az account set`.

    ```azurecli
    az account set --subscription "<subscription_id_or_subscription_name>"
    ```
    
    **Key points:**
    
    - Replace the `<subscription_id_or_subscription_name>` placeholder with the ID or name of the subscription you want to use.
    - Calling `az account set` doesn't display the results of switching to the specified Azure subscription. However, you can use `az account show` to confirm that the current Azure subscription has changed.
    - If you run the `az account list` command from the previous step, you see that the default Azure subscription has changed to the subscription you specified with `az account set`.
    
#### Create a service principal

Automated tools that deploy or use Azure services - such as Terraform - should always have restricted permissions. Instead of having applications sign in as a fully privileged user, Azure offers service principals.

The most common pattern is to interactively sign in to Azure, create a service principal, test the service principal, and then use that service principal for future authentication (either interactively or from your scripts).

##### [Bash](#tab/bash)

1. To create a service principal, sign in to Azure. After [authenticating to Azure via a Microsoft account](#authenticate-to-azure-via-a-microsoft-account), return here.

1. If you're creating a service principal from Git Bash, set the `MSYS_NO_PATHCONV` environment variable. (This step isn't necessary if you're using Cloud Shell.)

    ```bash
    export MSYS_NO_PATHCONV=1    
    ```

    **Key points:**

    - You can set the `MSYS_NO_PATHCONV` environment variable globally (for all terminal sessions) or locally (for just the current session). As creating a service principal isn't something you do often, the sample sets the value for the current session. To set this environment variable globally, add the setting to the `~/.bashrc` file.

1. To create a service principal, run `az ad sp create-for-rbac`.

    ```azurecli
    az ad sp create-for-rbac --name <service_principal_name> --role Contributor --scopes /subscriptions/<subscription_id>
    ```

    **Key points:**

    - You can replace the `<service-principal-name>` with a custom name for your environment or omit the parameter entirely. If you omit the parameter, the service principal name is generated based on the current date and time.
    - Upon successful completion, `az ad sp create-for-rbac` displays several values. The `appId`, `password`, and `tenant` values are used in the next step.
    - The password can't be retrieved if lost. As such, you should store your password in a safe place. If you forget your password, you can [reset the service principal credentials](https://learn.microsoft.com/en-us/cli/azure/azure-cli-sp-tutorial-7?tabs=bash).
    - For this article, a service principal with a **Contributor** role is being used. For more information about Role-Based Access Control (RBAC) roles, see [RBAC: Built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles).
    - The output from creating the service principal includes sensitive credentials. Be sure that you don't include these credentials in your code or check the credentials into your source control.
    - For more information about options when creating a service principal with the Azure CLI, see the article [Create an Azure service principal with the Azure CLI](https://learn.microsoft.com/en-us/cli/azure/azure-cli-sp-tutorial-1?tabs=bash).

##### [Azure PowerShell](#tab/azure-powershell)

1. Open a PowerShell prompt.

1. Run `Connect-AzAccount`.

    ```powershell
    Connect-AzAccount
    ```

    **Key points:**

    - Upon successful sign in, `Connect-AzAccount` displays information about the default subscription.
    - Make note of the `TenantId` as it's needed to use the service principal.

1. To confirm the current Azure subscription, run `Get-AzContext`.

    ```powershell
    Get-AzContext
    ```

1. To view all enabled Azure subscriptions for the logged-in Microsoft account, run `Get-AzSubscription`.

    ```azurecli
    Get-AzSubscription
    ```

1. To use a specific Azure subscription, run `Set-AzContext`.

    ```powershell
    Set-AzContext -Subscription "<subscription_id_or_subscription_name>"
    ```
    
    **Key points:**
    
    - Replace the `<subscription_id_or_subscription_name>` placeholder with the ID or name of the subscription you want to use.

1. Run `New-AzADServicePrincipal` to create a new service principal.

    ```powershell
    $sp = New-AzADServicePrincipal -DisplayName <service_principal_name> -Role "Contributor"
    ```

    **Key points:**

    - You can replace the `<service-principal-name>` with a custom name for your environment or omit the parameter entirely. If you omit the parameter, the service principal name is generated based on the current date and time.
    - The **Contributor** role is being used. For more information about Role-Based Access Control (RBAC) roles, see [RBAC: Built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles).

1. Display the service principal ID.

    ```powershell
    $sp.AppId
    ```

    **Key points:**

    - Make note of the service principal application ID as it's needed to use the service principal.

1. Get the autogenerated password to text.

    ```powershell
    $sp.PasswordCredentials.SecretText
    ```

    **Key points:**
    
    - Make note of the password as it's needed to use the service principal.
    - The password can't be retrieved if lost. As such, you should store your password in a safe place. If you forget your password, you can [reset the service principal credentials](https://learn.microsoft.com/en-us/cli/azure/azure-cli-sp-tutorial-7?tabs=bash).

---

#### Specify service principal credentials in environment variables

Once you create a service principal, you can specify its credentials to Terraform via environment variables.

##### [Bash](#tab/bash)

1. Edit the `~/.bashrc` file by adding the following environment variables.

    ```bash
    export ARM_SUBSCRIPTION_ID="<azure_subscription_id>"
    export ARM_TENANT_ID="<azure_subscription_tenant_id>"
    export ARM_CLIENT_ID="<service_principal_appid>"
    export ARM_CLIENT_SECRET="<service_principal_password>"
    ```

1. To execute the `~/.bashrc` script, run `source ~/.bashrc` (or its abbreviated equivalent `. ~/.bashrc`). You can also exit and reopen Cloud Shell for the script to run automatically.

    ```bash
    . ~/.bashrc
    ```

1. Once the environment variables have been set, you can verify their values as follows:

    ```bash
    printenv | grep ^ARM*
    ```


##### [Azure PowerShell](#tab/azure-powershell)

1. To set the environment variables within a specific PowerShell session, use the following code. Replace the placeholders with the appropriate values for your environment.

    ```powershell
    $env:ARM_CLIENT_ID="<service_principal_app_id>"
    $env:ARM_SUBSCRIPTION_ID="<azure_subscription_id>"
    $env:ARM_TENANT_ID="<azure_subscription_tenant_id>"
    $env:ARM_CLIENT_SECRET="<service_principal_password>"
    ```

1. Run the following PowerShell command to verify the Azure environment variables:

    ```powershell
    gci env:ARM_*
    ```

1. To set the environment variables for every PowerShell session, [create a PowerShell profile](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.4) and set the environment variables within your profile.

**Key points:**

- As with any environment variable, to access an Azure subscription value from within a Terraform script, use the following syntax: `${env.<environment_variable>}`. For example, to access the `ARM_SUBSCRIPTION_ID` value, specify `${env.ARM_SUBSCRIPTION_ID}`.
- Creating and applying Terraform execution plans makes changes on the Azure subscription associated with the service principal. This fact can sometimes be confusing if you're logged into one Azure subscription and the environment variables point to a second Azure subscription. Let's look at the following example to explain. Let's say you have two Azure subscriptions: SubA and SubB. If the current Azure subscription is SubA (determined via `az account show`) while the environment variables point to SubB, any changes made by Terraform are on SubB. Therefore, you would need to log in to your SubB subscription to run Azure CLI commands or Azure PowerShell commands to view your changes.
---

#### Specify service principal credentials in a Terraform provider block

The Azure provider block defines syntax that allows you to specify your Azure subscription's authentication information.

```terraform
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id   = "<azure_subscription_id>"
  tenant_id         = "<azure_subscription_tenant_id>"
  client_id         = "<service_principal_appid>"
  client_secret     = "<service_principal_password>"
}

# Your code goes here
```
### Terraform Files
***

- `*.main.tf`: This is the file that declares what infrastructure should be provisioned by Terraform. 
- `*.vars.tf`: This file declares your variables, their type, and some have default values where we recommend.
- `*.tfvars`: This file defines your variables by assigning them a value using a simple key/value pair format.
- `*.output.tf`: This file tells Terraform what to output to the end-user after the deployment is complete.

### The Variables

The main variables file that you'll need to focus on is `*.tfvars`. We have it pre-loaded with all required variables that must be assigned a value. There are other variables that have a default value loaded into in our `*.vars.tf` file, but feel free to override those values in the `*.tfvars` file.

These variable names should be pretty self-explanitory and have descriptions that explain what they do in the `*.vars.tf` file and listed below. They are split into groups that explain how they are used.

#### Variables with no default values

The below variables are pre-loaded in the `*.tfvars` file and must be assigned a value

**Existing & New VNet**
- `agentvmregion` - ***(string)*** The region that you will use to spin up temporary testing agents using the Azure VM Agent Plugin. These need to be in the format: East US, West US, East US 2, etc. The space is required. _(Example: East US )_
- `env_tag` - ***(string)*** An environment tag to tag all applicable resources with the environment. _(Example: development)_
- `os_type` - ***(string)*** The Linux distribution that will be installed on the Jenkins manager virtual machine. We currently support Ubuntu 22.04 (`ubuntu`), and Red Hat Enterprise Linux (RHEL) 9.4 (`redhat`). _(Example: ubuntu OR redhat)_
- `jenkinsadmin` - ***(string)*** Default Jenkins admin user that we will create for you via automation. _(Example: cycleadmin )_
- `jenkinspassword` - ***(string)*** Default Jenkins admin user password that we will assign to the admin user that was created. _(Example: @ppL1@ncEP@$$w0rd! )_
- `jenkinsvmname` - ***(string)*** The name of the Jenkins Manager Azure virtual machine. _(Example: jenkins-mgr)_
- `owner_tag` - ***(string)*** An owner tag to tag all applicable resources with the resource owner. _(Example: ryan-berger)_
- `resource_group_location` - ***(string)*** The region that all of the Cycle Appliance resources will be deployed into. _(Example: eastus )_
- `ssh_key_name` - ***(string)*** Name of the SSH keypair file(s) within the **/keys/** directory that you created using ssh-keygen. We will append the .pub and .pem.. _(Example: cycleappliancekey)_
- `subscription_id` - ***(string)*** The subscription ID of the Azure subscription you will be deploying into. _(Example: 1234-5678-xxxx-xxxx-xxxx)_

**Existing VNet only**
- `existing_subnet_name` - ***(string)*** The name of the existing subnet that you will be connecting the Cycle Appliance to. _(Example: main-snet)_
- `existing_vnet_name` - ***(string)*** The name of the existing virtual network that you will be connecting the Cycle Appliance to. _(Example: cyclelabs-vnet)_
- `existing_vnet_rg_name` - ***(string)*** The resource group that the existing virtual network lives in. _(Example: existing-vnet-rg)_

**New VNet only**
- `subnet_address_space` - ***(list)*** The CIDR range for the new subnet that will be created within the new virtual network. _(Example: 10.0.10.0/24)_
- `vnet_address_space` - ***(list)*** The CIDR range for the new virtual network that will be created. _(Example: 10.0.10.0/16)_

#### Variables with default values
The below variable are not pre-loaded in the `*.tfvars` as they have default values in the `*.vars.tf` file, but feel free to override any of these default values by pulling the key/value pairs from the snippet below these descriptions

- `resource_name_prefix` - ***(string)*** A prefix for the name of all resources deployed with this code _(Example: cycleappliance)_
- `jenkins_mgr_sku` - ***(string)*** The VM SKU for the Jenkins Manager. We recommend a minimum instance SKU of Standard_DS1_v2, but if you want to increase the SKU you can do so. NOTE: We decided to use Azure VM SKU's without temporary disks attached, as we do not leverage these at all for the Jenkins Manager. _(Example: Standard_D2_v4)_
- `agentadminusername` - ***(string)*** The agent Admin username needed to connect to the agent with Jenkins (We've defaulted to using the default username defined in our Packer Template for CycleReady Images for your convenience) _(Example: administrator)_
- `agentadminpassword` - ***(string)*** The agent Admin password needed to connect to the agent with Jenkins (We've defaulted to using the default password defined in our Packer Template for CycleReady Images for your convenience) _(Example: 68q79h4W#mN4k87P#!JQ)_
- `backup_frequency` - ***(string)*** The frequency of the backup. _(Example: Daily)_
- `backup_time` - ***(string)*** The time at which the backup is taken. _(Example: 23:00)_
- `retention_daily_count` - ***(number)*** The number of daily retention points. _(Example: 7)_
- `retention_weekly_count` - ***(number)*** The number of weekly retention points. _(Example: 8)_
- `retention_weekly_days` - ***(list(string))*** The days of the week for weekly retention. _(Example: ["Sunday", "Wednesday"])_

```
resource_name_prefix    = "<input>"
jenkins_mgr_sku         = "<input>"
agentadminusername      = "<input>"
agentadminpassword      = "<input>"
backup_frequency        = "<input>"
backup_time             = "<input>"
retention_daily_count   = <input>
retention_weekly_count  = <input>
retention_weekly_days   = ["<input>,<input>"]
```

<!-- 
### Declaring Variables
***

There is a `variables.tf` file in each of the Cycle Appliance folders (`new-vnet`, `existing-vnet`). These variables will need to be altered to fit your environment. ***If joining the deployment to an existing VNet, `existing_subnet_name, existing_vnet_name, existing_vnet_rg_name` will need to be configured - these do not exist in the `variables.tf` for the `new-vnet`.*** 

These variable names should be self-explanitory and have descriptions that explain what they do. They are split into groups that explain how they are used. You'll want to go through this list and make sure that each of these have values in them. The only exceptions are `agentadminpasword` and `jenkinspassword`, since these are both sensitive values we kept them blank. They will need to be specified at the time of running `terraform plan` and `terraform apply` - or configured as variables within Terraform Cloud if it is being used. -->

### Generating SSH keypair
***

In order to secure the environment, it is required to generate an SSH keypair and then place the public key into the `/keys` folder within the `cycle-appliance-*` folder. Our code looks for a public key with the value of the variable `ssh_key_name`. We use this value to assign a public key to the Jenkins Manager VM, as well as generating the connection string to SSH into that machine using the private key. This key pair should be kept secure and stored somewhere.

1. Run `ssh-keygen` and create a keypair.
2. Copy the public key file (`.pub`) to the `/cycle-appliance-*-vnet/keys/` directory.
3. Update `*.vars.tf` to reference the SSH key name - we append the .pub so you don't need to include this.
4. You're good to go, now when the deployment runs, it will use the public key in the `/keys` directory for the Jenkkins manager virtual machine.
5. If you need to directly connect to the Jenkins manager, you'll use the private key (`.pem`) to authenticate.

```
ssh-keygen
Generating public/private rsa key pair.
Enter file in which to save the key (/Users/ryan/.ssh/id_rsa): your-ssh-pub
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in your-ssh-pub
Your public key has been saved in your-ssh-pub.pub
The key fingerprint is:
SHA256:tUj0NJG87/ZO/39QOvHQUxc0krl2VoVKz4eDsJ3NIeA ryan@Ryans-MBP.localdomain
The key's randomart image is:
+---[RSA 3072]----+
|        ..=+ .+=+|
|       . ++.oo+ =|
|        . E* X.++|
|       . oo.=oX++|
|        S ... oO.|
|            . + .|
|           .  .o |
|            o. ..|
|           . oo B|
+----[SHA256]-----+
cp your-ssh-pub.pub ~/Documents/GitHub/terraform/azure/cycleappliance/cycle-appliance-existing-vnet/keys/
cd ~/Documents/GitHub/terraform/azure/cycleappliance/cycle-appliance-existing-vnet/keys/
cat your-ssh-pub.pub
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDGwHJpbOMqY2xK8C/nUSLGMeBLB+fkB6GxUyJ8BZn5MoTmj8aGZrT7wTXP9LordwtWptI1qn4oBolcZ90swHwNz1qHEYbhg575RoaepIoG3ToKMDgnWz4Tx8wzbvdd9iPYEOyLEwFOEz2tX8aIsqZ4Ja3aFS83GQtqiGGGnH+aTGl9O3hx9G21Cl//nD8Cy+6PCNpzLd9gvW46s/+NYmimRpF/blylz4Xn/cnBgACk= ryan@Ryans-MBP.localdomain
```
### Networking Considerations
***

Due to the complexities and requirements of our customers, we built our Cycle Appliance to be deployed in two different styles: onto an entirely new virtual network, or to join an existing virtual network. Within the root folder of the repository, you will see a Cycle Appliance folder for both of these configuration types: `cycle-appliance-new-vnet` and `cycle-appliance-existing-vnet`.

The Jenkins agent Security Group this builds is set to allow all traffic from the private CIDR. If you'd like to scope this down using the Principle of Least Privilege, the necessary ports for Jenkins manager to agent connection are listed below. 

WinRM: TCP 5985
WinRM (HTTPS): TCP 5986
SMB: 445

#### Deploying to a new Virtual Network

With a new network deployment, there is nothing you need to configure if you do not need to deploy this with a custom address space. Simply apply the Terraform code with the default settings in `variables.tf` and it will build a private Virtual Network with the address space of: `10.0.0.0/22`, and a single subnet with an address space of: `10.0.1.0/24`. (If you need to customize these, change them in `variables.tf` - they are configured with `new_vnet_address_space` and `new_vnet_subnet_address_space`). The Jenkins manager and all of the testing agents will be deployed onto this single subnet. This Virtual Network will need to be peered with a Virtual Network that can communicate with your WMS environment, so that the testing agents can communicate with it.

#### Deploying to an existing Virtual Network

If deploying to an existing Virtual Network, you will need to take into consideration regional requirements from in Azure. If your existing Virtual Network is on the East US 2 region, you should also deploy your Cycle Appliance to the East US 2 region. This is a good option for customers who have an existing network within Azure that already has connectivity set up to their WMS environments, so we wanted to allow customers to just put their Cycle Appliance onto that existing network architecture. 

You will need to make sure the variables `existing_subnet_name`, `existing_vnet_name`, `existing_vnet_rg_name` are configured in `variables.tf` with the appropriate values. This will join the Jenkins manager to the Virtual Network and Subnet that you specified, and also configure Jenkins to put testing agents onto this Virtual Network and Subnet. ***There is a role requirement on the existing Virtual Network to allow the Managed Identity to join new Virtual Machines to it, more about how to configure that below:***
- If you deployed the `./cyclle-appliance-existing-vnet` configuration, you will need to give the newly created Managed Identity the `Virtual Network Contributor` RBAC role on the Virtual Network you are using. The Managed Identity needs action: `Microsoft.Network/virtualNetworks/subnet/join/action` in order to perform the task of joining a new NIC to the virtual network. Navigate to the existing Virtual Network, select Access Control (IAM), Add, selected `Managed Identity`, add the newly created Jenkins manager virtual machine. After about 5 minutes, the access will propagate over to the `Identity` blade within the Jenkins manager virtual machine under `Role Assignments`, once it shows up there - you're good to go.


## Deploying the Cycle Appliance with Terraform
***

### Local Deployment
1. Change directories into the Cycle Appliance project folder; `./cycle-appliance-new-vnet` or `./cycle-appliance-existing-vnet`.
2. Run `terraform init` to initialize the project. This will download the providers and get `terraform` ready to run `plan` and `apply` commands.
3. Run `terraform validate` to make sure there are no syntaxual issues with any of the `*.tf` files.
4. Make sure you've either configured your local workspace with the required Azure environment variables to authenticate with a service principal, or have authenticated with `az login` and properly set your Azure subscription with `az account set --subscription SUBSCRIPTION_ID`.
    - Refer to [Authenticate to Azure](#authenticate-to-azure)
5. Run `terraform plan` to generate a tentative plan of what will be deployed, since we do not store passwords in the `variables.tf` file - it will prompt you to set the `agentadminpassword` and `jenkinspassword` variables at runtime.
    - ![Image](https://cycldocimgs.blob.core.windows.net/docimgs/plan.png)
    - `agentadminpassword` is the password that will be set for the local admin accounts for the Windows agent virtual machines; it needs to be `12` characters long or more to meet Azure requirements.
    - `jenkinspassword` is the password that will be set for the Jenkins administrator account that we create. This has no length requirements.
6. Your `terraform plan` will output what will be built; so you can review this and make sure everything looks good. If it does, you can proceed.
7. Finally, you can run `terraform apply` to deploy the resources to Azure. Terraform will show you output of everything it is building; and tell you when it's completed the deployment of each resource. This process will take about 3 minutes to complete.
    - ![Image](https://cycldocimgs.blob.core.windows.net/docimgs/aws-apply.png)
8. Once the `terraform apply` is finished, the initialization script will still be running on the Jenkins manager to do a lot of the heavy lifting. You should allow `5 minutes` before connecting this server to try and do everything.
    - If you deployed the `./cycle-appliance-new-vnet` configuration, you will need to peer that private Virtual Network with a network you can access within your Azure tenant before you can SSH into the box.
    - If you deployed the `./cyclle-appliance-existing-vnet` configuration, you will need to give the newly created Managed Identity the `Virtual Network Contributor` RBAC role on the Virtual Network you are using. The Managed Identity needs action: `Microsoft.Network/virtualNetworks/subnet/join/action` in order to perform the task of joining a new NIC to the virtual network. Navigate to the existing Virtual Network, select Access Control (IAM), Add, selected `Managed Identity`, add the newly created Jenkins manager virtual machine. After about 5 minutes, the access will propagate over to the `Identity` blade within the Jenkins manager virtual machine under `Role Assignments`, once it shows up there - you're good to go.
9. You will be able to access the Jenkins Manager using the private IP, on port `8080` - or just by using the `jenkins_manager` output value.
    - You'll be able to login with the values for `var.jenkinsadmin` and `var.jenkinspassword`. 
    - OR if you want to access the Jenkins Manager virtual machine with SSH; you can use the private key you created with the `var.jenkinsadmin` username. The automation will associate your public key that you placed in the `/keys` folder with that username.
10. Our automation configures the Jenkins Manager so that it's about 95% of the way to being configured to start testing with Cycle. The last step is altering the image that is used for agent creation. By default, we set this to use the standard Windows Server 2019 DataCenter from the Azure marketplace. This is great to test that Jenkins is able to talk back to Azure, and provision / deprovision testing agents. You will want to create a golden image that has Cycle and other necessary tools on it, and then utilize that image within Jenkins. Thankfully, we've also built automation to help you do this using Packer. That documentation is located [here](https://dev.azure.com/cyclelabs/cycle-codetemplates/_git/packer?path=/azure/cycleready) 
    - Once you create this image, you can configure it to be used in the **Cloud Config** area of **Manage Jenkins**.
### Terraform Cloud Deployment


## Help, Questions, and Feedback
If you have need assistance, have questions, or want to provide feedback - we're here for you! You can reach our Cloud Engineering team at: [cloudengineering@cyclelabs.io](mailto:cloudengineering@cyclelabs.io?subjectCycle%20Appliance@Help)

## Change Log 
- 06/21/2024 - We added the `os_type` variable to the Cycle Appliance for Azure. This variable can be set to either `ubuntu` or `redhat` and depending on the value, it will properly deploy the latest version of the selected operating system (Ubuntu 22.04, and RHEL 9.4) and also handle all of the post configuration via the respective `cloud-init` script. For Ubuntu, it will use the `cloud-init-tf.yml`, and for Red Hat, it will use the `rhel-cloud-init-tf.yml`.