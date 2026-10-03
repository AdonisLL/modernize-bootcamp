param prefix string
param suffix string
param regionLabel string
param location string
param databaseAddressPrefix string
param applicationAddressPrefix string
param applicationLocation string = location
param enablePrimaryServices bool = false
param enableManagedInstanceSubnet bool = false
param enableApplicationVnet bool = true
param tags object = {}

var databaseVnetName = '${prefix}-db-${regionLabel}-${suffix}-vnet'
var applicationVnetName = '${prefix}-app-${regionLabel}-${suffix}-vnet'
var databaseSecondOctet = split(databaseAddressPrefix, '.')[1]
var applicationSecondOctet = split(applicationAddressPrefix, '.')[1]
var managedInstanceAddressPrefix = '10.${databaseSecondOctet}.5.0/24'
var managedInstanceAddressToken = replace(replace(managedInstanceAddressPrefix, '.', '-'), '/', '-')

resource vmNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (enablePrimaryServices) {
  name: '${prefix}-vm-${suffix}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRdpFromBastion'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '10.${databaseSecondOctet}.1.0/26'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowSshFromBastion'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.${databaseSecondOctet}.1.0/26'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource databaseVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: databaseVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        databaseAddressPrefix
      ]
    }
  }
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (enablePrimaryServices) {
  parent: databaseVnet
  name: 'AzureBastionSubnet'
  properties: {
    addressPrefix: '10.${databaseSecondOctet}.1.0/26'
  }
}

resource vmSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (enablePrimaryServices) {
  parent: databaseVnet
  name: 'snet-vms'
  dependsOn: [
    bastionSubnet
  ]
  properties: {
    addressPrefix: '10.${databaseSecondOctet}.2.0/24'
    networkSecurityGroup: {
      id: vmNsg.id
    }
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (enablePrimaryServices) {
  parent: databaseVnet
  name: 'snet-private-endpoints'
  dependsOn: [
    vmSubnet
  ]
  properties: {
    addressPrefix: '10.${databaseSecondOctet}.3.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource dmsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (enablePrimaryServices) {
  parent: databaseVnet
  name: 'snet-dms'
  dependsOn: [
    privateEndpointSubnet
  ]
  properties: {
    addressPrefix: '10.${databaseSecondOctet}.4.0/24'
  }
}

resource managedInstanceNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (enableManagedInstanceSubnet) {
  name: '${prefix}-sqlmi-${suffix}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSqlFromVirtualNetwork'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-healthprobe-in-${managedInstanceAddressToken}-v12'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: managedInstanceAddressPrefix
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-internal-in-${managedInstanceAddressToken}-v12'
        properties: {
          priority: 101
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: managedInstanceAddressPrefix
          destinationAddressPrefix: managedInstanceAddressPrefix
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-internal-out-${managedInstanceAddressToken}-v12'
        properties: {
          priority: 101
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: managedInstanceAddressPrefix
          destinationAddressPrefix: managedInstanceAddressPrefix
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-optional-azure-out-${managedInstanceAddressToken}'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Outbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: managedInstanceAddressPrefix
          destinationAddressPrefix: 'AzureCloud'
        }
      }
    ]
  }
}

resource managedInstanceRouteTable 'Microsoft.Network/routeTables@2024-05-01' = if (enableManagedInstanceSubnet) {
  name: '${prefix}-sqlmi-${suffix}-rt'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_subnet-${managedInstanceAddressToken}-to-vnetlocal'
        properties: {
          addressPrefix: managedInstanceAddressPrefix
          nextHopType: 'VnetLocal'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_optional-AzureCloud.${location}'
        properties: {
          addressPrefix: 'AzureCloud.${location}'
          nextHopType: 'Internet'
        }
      }
    ]
  }
}

resource managedInstanceSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (enableManagedInstanceSubnet) {
  parent: databaseVnet
  name: 'snet-sqlmi'
  dependsOn: [
    dmsSubnet
  ]
  properties: {
    addressPrefix: managedInstanceAddressPrefix
    networkSecurityGroup: {
      id: managedInstanceNsg.id
    }
    routeTable: {
      id: managedInstanceRouteTable.id
    }
    delegations: [
      {
        name: 'managed-instance'
        properties: {
          serviceName: 'Microsoft.Sql/managedInstances'
        }
      }
    ]
  }
}

resource applicationVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = if (enableApplicationVnet) {
  name: applicationVnetName
  location: applicationLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        applicationAddressPrefix
      ]
    }
  }
}

resource containerAppsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (enableApplicationVnet) {
  parent: applicationVnet
  name: 'snet-container-apps'
  properties: {
    addressPrefix: '10.${applicationSecondOctet}.0.0/23'
    delegations: [
      {
        name: 'container-apps'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource appToDatabase 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = if (enableApplicationVnet) {
  parent: applicationVnet
  name: 'app-to-database'
  dependsOn: [
    bastionSubnet
    vmSubnet
    privateEndpointSubnet
    dmsSubnet
    managedInstanceSubnet
    containerAppsSubnet
  ]
  properties: {
    remoteVirtualNetwork: {
      id: databaseVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource databaseToApp 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = if (enableApplicationVnet) {
  parent: databaseVnet
  name: 'database-to-app'
  dependsOn: [
    appToDatabase
  ]
  properties: {
    remoteVirtualNetwork: {
      id: applicationVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

output databaseVnetId string = databaseVnet.id
output databaseVnetName string = databaseVnet.name
output applicationVnetId string = enableApplicationVnet ? applicationVnet.id : ''
output applicationVnetName string = enableApplicationVnet ? applicationVnet.name : ''
output containerAppsSubnetId string = enableApplicationVnet ? containerAppsSubnet.id : ''
output bastionSubnetId string = enablePrimaryServices ? bastionSubnet.id : ''
output vmSubnetId string = enablePrimaryServices ? vmSubnet.id : ''
output privateEndpointSubnetId string = enablePrimaryServices ? privateEndpointSubnet.id : ''
output dmsSubnetId string = enablePrimaryServices ? dmsSubnet.id : ''
output managedInstanceSubnetId string = enableManagedInstanceSubnet ? managedInstanceSubnet.id : ''
