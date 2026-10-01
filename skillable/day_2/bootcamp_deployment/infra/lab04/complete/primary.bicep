targetScope = 'resourceGroup'

@minLength(3)
@maxLength(18)
param prefix string = 'caldova-lab04'

@minLength(8)
@maxLength(8)
param suffix string

param location string = 'centralus'

@allowed([
  'azureSql'
  'sqlMi'
])
param databaseMode string = 'sqlMi'

param codeBuildPrincipalId string
param sqlEntraAdminObjectId string
param sqlEntraAdminLogin string

@allowed([
  'User'
  'Group'
  'Application'
])
param sqlEntraAdminPrincipalType string = 'User'

@secure()
param vmAdminUsername string

@secure()
param vmAdminPassword string

param tags object = {
  Application: 'Caldova'
  Environment: 'Lab'
  ManagedBy: 'Bicep'
}

var nameToken = take(replace(prefix, '-', ''), 12)
var registryName = toLower('${nameToken}cr${suffix}')
var sqlServerName = toLower('${nameToken}sql${suffix}')

module network './modules/regional-network.bicep' = {
  name: 'primary-network'
  params: {
    prefix: prefix
    suffix: suffix
    regionLabel: 'primary'
    location: location
    databaseAddressPrefix: '10.0.0.0/20'
    applicationAddressPrefix: '10.20.0.0/20'
    enablePrimaryServices: true
    enableApplicationVnet: false
    tags: tags
  }
}

module registry './modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    name: registryName
    location: location
    tags: tags
  }
}

module codeBuildRegistryPush './modules/acr-push-role.bicep' = {
  name: 'code-build-acr-push'
  params: {
    containerRegistryName: registry.outputs.name
    principalId: codeBuildPrincipalId
  }
}

module machines './modules/virtual-machines.bicep' = {
  name: 'private-virtual-machines'
  params: {
    prefix: prefix
    suffix: suffix
    location: location
    subnetId: network.outputs.vmSubnetId
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    tags: tags
  }
}

module bastion './modules/bastion.bicep' = {
  name: 'bastion'
  params: {
    name: '${prefix}-${suffix}-bas'
    location: location
    subnetId: network.outputs.bastionSubnetId
    tags: tags
  }
}

module sql './modules/sql-database.bicep' = if (databaseMode == 'azureSql') {
  name: 'private-sql-database'
  params: {
    serverName: sqlServerName
    location: location
    entraAdminObjectId: sqlEntraAdminObjectId
    entraAdminLogin: sqlEntraAdminLogin
    entraAdminPrincipalType: sqlEntraAdminPrincipalType
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    databaseVnetId: network.outputs.databaseVnetId
    tags: tags
  }
}

module migration './modules/database-migration-service.bicep' = {
  name: 'database-migration-service'
  params: {
    name: '${prefix}-${suffix}-dms'
    location: location
    subnetId: network.outputs.dmsSubnetId
    tags: tags
  }
}

output containerRegistryName string = registry.outputs.name
output containerRegistryLoginServer string = registry.outputs.loginServer
output privateDnsZoneName string = databaseMode == 'azureSql'
  ? 'privatelink${environment().suffixes.sqlServerHostname}'
  : ''
output sqlServerName string = databaseMode == 'azureSql' ? sqlServerName : ''
output sqlServerFqdn string = databaseMode == 'azureSql'
  ? '${sqlServerName}${environment().suffixes.sqlServerHostname}'
  : ''
output sqlDatabaseName string = databaseMode == 'azureSql' ? 'eshop_ai' : ''
output databaseFqdn string = databaseMode == 'azureSql'
  ? '${sqlServerName}${environment().suffixes.sqlServerHostname}'
  : ''
output databaseVnetId string = network.outputs.databaseVnetId
output databaseVnetName string = network.outputs.databaseVnetName
output virtualMachineNames array = machines.outputs.virtualMachineNames
output virtualMachineIds array = machines.outputs.virtualMachineIds
output virtualMachinePrincipalIds array = machines.outputs.virtualMachinePrincipalIds
