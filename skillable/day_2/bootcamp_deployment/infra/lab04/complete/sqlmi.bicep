targetScope = 'resourceGroup'

@minLength(3)
@maxLength(18)
param prefix string = 'caldova-lab04'

@minLength(8)
@maxLength(8)
param suffix string

param location string = 'centralus'
param databaseVnetName string = '${prefix}-db-secondary-${suffix}-vnet'
param managedInstanceSubnetName string = 'snet-sqlmi'
param sqlEntraAdminObjectId string
param sqlEntraAdminLogin string

@allowed([
  'Freemium'
  'Regular'
])
param pricingModel string = 'Freemium'

@allowed([
  'User'
  'Group'
  'Application'
])
param sqlEntraAdminPrincipalType string = 'User'

param tags object = {
  Application: 'Caldova'
  Environment: 'Lab'
  ManagedBy: 'Bicep'
  Optional: 'SqlManagedInstance'
}

var nameToken = take(replace(prefix, '-', ''), 12)

resource databaseVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: databaseVnetName
}

resource managedInstanceSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: databaseVnet
  name: managedInstanceSubnetName
}

module managedInstance './modules/sql-managed-instance.bicep' = {
  name: 'sql-managed-instance'
  params: {
    name: toLower('${nameToken}mi${suffix}')
    location: location
    subnetId: managedInstanceSubnet.id
    entraAdminObjectId: sqlEntraAdminObjectId
    entraAdminLogin: sqlEntraAdminLogin
    entraAdminPrincipalType: sqlEntraAdminPrincipalType
    pricingModel: pricingModel
    tags: tags
  }
}

output managedInstanceName string = managedInstance.outputs.name
output managedInstanceFqdn string = managedInstance.outputs.fullyQualifiedDomainName
output managedInstancePublicEndpoint string = managedInstance.outputs.publicEndpoint
output managedDatabaseName string = 'eshop_ai'
