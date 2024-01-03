terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  features {}
}

resource "azurerm_resource_group" "mtc-rg" {
  name     = "mtc-resources"
  location = "West Europe"
  tags = {
    environment = "dev"
  }
}


resource "azurerm_virtual_network" "mtc-vn" {
  name                = "mtc-network"
  resource_group_name = azurerm_resource_group.mtc-rg.name
  location            = azurerm_resource_group.mtc-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "mtc-subnet" {
  name                 = "mtc-subnet"
  resource_group_name  = azurerm_resource_group.mtc-rg.name
  virtual_network_name = azurerm_virtual_network.mtc-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "mtc-sg" {
  name                = "mtc-sg"
  location            = azurerm_resource_group.mtc-rg.location
  resource_group_name = azurerm_resource_group.mtc-rg.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "mtc-dev-rules" {
  name                        = "mtc-dev-rules"
  resource_group_name         = azurerm_resource_group.mtc-rg.name
  network_security_group_name = azurerm_network_security_group.mtc-sg.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_subnet_network_security_group_association" "mtc-dev-subnet-assoc" {
  subnet_id                 = azurerm_subnet.mtc-subnet.id
  network_security_group_id = azurerm_network_security_group.mtc-sg.id
}


resource "azurerm_public_ip" "dev-pub-ip" {
  name                    = "dev-public-ip"
  location                = azurerm_resource_group.mtc-rg.location
  resource_group_name     = azurerm_resource_group.mtc-rg.name
  allocation_method       = "Dynamic"
  idle_timeout_in_minutes = 30

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "dev-nic" {
  name                = "dev-nic"
  location            = azurerm_resource_group.mtc-rg.location
  resource_group_name = azurerm_resource_group.mtc-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.mtc-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.dev-pub-ip.id
  }

  tags = {
    environment = "dev"
  }
}


resource "azurerm_linux_virtual_machine" "mtc-dev-vm" {
  name                  = "dev-machine"
  resource_group_name   = azurerm_resource_group.mtc-rg.name
  location              = azurerm_resource_group.mtc-rg.location
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.dev-nic.id]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser"
      identityfile = "~/.ssh/id_rsa"
    })
    interpreter = var.host_os == "linux" ? ["bash", "-c"] : ["PowerShell", "-Command"]
  }
}


data "azurerm_public_ip" "dev-pub-ip" {
  name                = azurerm_public_ip.dev-pub-ip.name
  resource_group_name = azurerm_resource_group.mtc-rg.name
}

output "vm_ip_addr" {
  value = "${azurerm_linux_virtual_machine.mtc-dev-vm.name}: ${data.azurerm_public_ip.dev-pub-ip.ip_address}"
}