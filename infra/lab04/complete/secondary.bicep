targetScope = 'resourceGroup'

@minLength(3)
@maxLength(18)
param prefix string = 'caldova-lab04'

@minLength(6)
@maxLength(6)
param suffix string

param location string = 'centralus'
param applicationLocation string = 'centralus'
param codeDeploymentPrincipalId string
param containerRegistryName string
param containerRegistryLoginServer string
param containerRegistryResourceGroupName string
param privateDnsZoneResourceGroupName string
param privateDnsZoneName string = 'privatelink${environment().suffixes.sqlServerHostname}'
param primaryDatabaseResourceGroupName string
param primaryDatabaseVnetName string
param primaryDatabaseVnetId string
param primaryDatabaseFqdn string
param runtimeIdentityResourceId string
param runtimeIdentityClientId string
param keyVaultSecretReferences array = []

param tags object = {
  Application: 'Caldova'
  Environment: 'Lab'
  ManagedBy: 'Bicep'
}

var nameToken = take(replace(prefix, '-', ''), 12)
var retailDatabaseName = 'eshop'

module network './modules/regional-network.bicep' = {
  name: 'secondary-network'
  params: {
    prefix: prefix
    suffix: suffix
    regionLabel: 'secondary'
    location: location
    databaseAddressPrefix: '10.1.0.0/20'
    applicationAddressPrefix: '10.20.0.0/20'
    applicationLocation: applicationLocation
    enableManagedInstanceSubnet: true
    tags: tags
  }
}

module monitoring './modules/monitor.bicep' = {
  name: 'application-monitoring'
  params: {
    name: '${prefix}-application-${suffix}-log'
    location: applicationLocation
    tags: tags
  }
}

module regionalApp './modules/container-app-region.bicep' = {
  name: 'application-container-apps'
  params: {
    prefix: nameToken
    suffix: suffix
    regionLabel: 'application'
    location: applicationLocation
    infrastructureSubnetId: network.outputs.containerAppsSubnetId
    logAnalyticsCustomerId: monitoring.outputs.customerId
    logAnalyticsSharedKey: monitoring.outputs.sharedKey
    containerRegistryLoginServer: containerRegistryLoginServer
    runtimeIdentityResourceId: runtimeIdentityResourceId
    runtimeIdentityClientId: runtimeIdentityClientId
    retailDatabaseFqdn: primaryDatabaseFqdn
    retailDatabaseName: retailDatabaseName
    keyVaultSecretReferences: keyVaultSecretReferences
    tags: tags
  }
}

module registryPull './modules/acr-pull-role.bicep' = {
  name: 'application-acr-pull'
  scope: resourceGroup(containerRegistryResourceGroupName)
  params: {
    containerRegistryName: containerRegistryName
    principalId: regionalApp.outputs.principalId
  }
}

module codeDeploymentAppContributor './modules/container-app-contributor-role.bicep' = {
  name: 'code-deployment-container-app-contributor'
  params: {
    containerAppName: regionalApp.outputs.appName
    principalId: codeDeploymentPrincipalId
  }
}

module secondaryDatabaseDns './modules/private-dns-link-cross-rg.bicep' = {
  name: 'secondary-database-dns'
  scope: resourceGroup(privateDnsZoneResourceGroupName)
  params: {
    privateDnsZoneName: privateDnsZoneName
    virtualNetworkId: network.outputs.databaseVnetId
    linkName: 'secondary-database-link'
    tags: tags
  }
}

module secondaryApplicationDns './modules/private-dns-link-cross-rg.bicep' = {
  name: 'application-database-dns'
  scope: resourceGroup(privateDnsZoneResourceGroupName)
  params: {
    privateDnsZoneName: privateDnsZoneName
    virtualNetworkId: network.outputs.applicationVnetId
    linkName: 'application-link'
    tags: tags
  }
}

module applicationToPrimaryDatabasePeering './modules/database-vnet-peering.bicep' = {
  name: 'application-to-primary-database-peering'
  params: {
    localVnetName: network.outputs.applicationVnetName
    remoteVnetId: primaryDatabaseVnetId
    peeringName: 'application-to-primary-database'
  }
}

module primaryDatabaseToApplicationPeering './modules/database-vnet-peering.bicep' = {
  name: 'primary-database-to-application-peering'
  scope: resourceGroup(primaryDatabaseResourceGroupName)
  params: {
    localVnetName: primaryDatabaseVnetName
    remoteVnetId: network.outputs.applicationVnetId
    peeringName: 'primary-database-to-application'
  }
}

module primaryToSecondaryDatabasePeering './modules/database-vnet-peering.bicep' = {
  name: 'primary-to-secondary-database-peering'
  scope: resourceGroup(primaryDatabaseResourceGroupName)
  params: {
    localVnetName: primaryDatabaseVnetName
    remoteVnetId: network.outputs.databaseVnetId
    peeringName: 'primary-to-secondary'
  }
}

module secondaryToPrimaryDatabasePeering './modules/database-vnet-peering.bicep' = {
  name: 'secondary-to-primary-database-peering'
  params: {
    localVnetName: network.outputs.databaseVnetName
    remoteVnetId: primaryDatabaseVnetId
    peeringName: 'secondary-to-primary'
  }
}

output containerAppName string = regionalApp.outputs.appName
output containerAppFqdn string = regionalApp.outputs.appFqdn
output containerAppsEnvironmentId string = regionalApp.outputs.environmentId
output containerAppsEnvironmentName string = regionalApp.outputs.environmentName
output applicationVnetId string = network.outputs.applicationVnetId
output applicationVnetName string = network.outputs.applicationVnetName
output databaseVnetId string = network.outputs.databaseVnetId
output databaseVnetName string = network.outputs.databaseVnetName
output managedInstanceSubnetId string = network.outputs.managedInstanceSubnetId
output retailDatabaseName string = retailDatabaseName
