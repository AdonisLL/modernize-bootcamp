param serverName string
param location string
param entraAdminObjectId string
param entraAdminLogin string

@allowed([
  'User'
  'Group'
  'Application'
])
param entraAdminPrincipalType string = 'User'

param privateEndpointSubnetId string
param databaseVnetId string
param tags object = {}

var sqlPrivateDnsZoneName = 'privatelink${environment().suffixes.sqlServerHostname}'

resource server 'Microsoft.Sql/servers@2023-08-01' = {
  name: serverName
  location: location
  tags: tags
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: entraAdminLogin
      principalType: entraAdminPrincipalType
      sid: entraAdminObjectId
      tenantId: subscription().tenantId
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: sqlPrivateDnsZoneName
  location: 'global'
  tags: tags
}

resource databaseDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: 'primary-database-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: databaseVnetId
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${serverName}-pe'
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${serverName}-connection'
        properties: {
          privateLinkServiceId: server.id
          groupIds: [
            'sqlServer'
          ]
          privateLinkServiceConnectionState: {
            status: 'Approved'
            description: 'Approved by the Lab 04 deployment.'
          }
        }
      }
    ]
    subnet: {
      id: privateEndpointSubnetId
    }
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sql'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

output serverId string = server.id
output serverName string = server.name
output serverFqdn string = server.properties.fullyQualifiedDomainName
output privateDnsZoneName string = privateDnsZone.name
