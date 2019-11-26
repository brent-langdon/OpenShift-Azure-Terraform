resource "azurerm_virtual_network" "osvnet" {
  name                = "${var.openshift_azure_resource_prefix}-vnet-${var.openshift_azure_resource_suffix}"
  depends_on          = [azurerm_resource_group.osrg]
  resource_group_name = azurerm_resource_group.osrg.name
  location            = azurerm_resource_group.osrg.location
  address_space       = [var.openshift_azure_infra_vm_address_space]
}

resource "azurerm_subnet" "osmastersubnet" {
  name                      = "osmastersubnet"
  depends_on                = [azurerm_virtual_network.osvnet]
  resource_group_name       = azurerm_resource_group.osrg.name
  virtual_network_name      = azurerm_virtual_network.osvnet.name
  network_security_group_id = azurerm_network_security_group.osmasternsg.id
  address_prefix            = var.openshift_azure_master_subnet_address_prefix
}

resource "azurerm_subnet" "osnodesubnet" {
  name                      = "osnodesubnet"
  depends_on                = [azurerm_virtual_network.osvnet]
  resource_group_name       = azurerm_resource_group.osrg.name
  virtual_network_name      = azurerm_virtual_network.osvnet.name
  network_security_group_id = azurerm_network_security_group.osnodensg.id
  address_prefix            = var.openshift_azure_node_subnet_address_prefix
}

resource "azurerm_network_security_group" "osmasternsg" {
  name                = "${var.openshift_azure_resource_prefix}-nsg-master-${var.openshift_azure_resource_suffix}"
  location            = azurerm_resource_group.osrg.location
  resource_group_name = azurerm_resource_group.osrg.name

  security_rule {
    name                       = "allowSSHin_all"
    description                = "Allow SSH in from all locations"
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
    name                       = "allowHTTPS_all"
    description                = "Allow HTTPS connections from all locations"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allowOpenShiftConsoleIn_all"
    description                = "Allow OpenShift Console connections from all locations"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "TCP"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "osnodensg" {
  name                = "${var.openshift_azure_resource_prefix}-nsg-node-${var.openshift_azure_resource_suffix}"
  location            = azurerm_resource_group.osrg.location
  resource_group_name = azurerm_resource_group.osrg.name

  security_rule {
    name                       = "allowSSHin_all"
    description                = "Allow SSH in from all locations"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allowHTTPSIn_all"
    description                = "Allow HTTPS traffic from the Internet to Public Agents"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allowHTTPIn_all"
    description                = "Allow HTTP connections from all locations"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "osinfransg" {
  name                = "${var.openshift_azure_resource_prefix}-nsg-infra-${var.openshift_azure_resource_suffix}"
  location            = azurerm_resource_group.osrg.location
  resource_group_name = azurerm_resource_group.osrg.name

  security_rule {
    name                       = "allowSSHin_all"
    description                = "Allow SSH in from all locations"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allowHTTPSIn_all"
    description                = "Allow HTTPS traffic from the Internet to Public Agents"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allowHTTPIn_all"
    description                = "Allow HTTP connections from all locations"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
