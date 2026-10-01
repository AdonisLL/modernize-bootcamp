param name string
param location string
param subnetId string
param entraAdminObjectId string
param entraAdminLogin string

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
param entraAdminPrincipalType string = 'User'

param tags object = {}

resource managedInstance 'Microsoft.Sql/managedInstances@2023-08-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 4
  }
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: entraAdminLogin
      principalType: entraAdminPrincipalType
      sid: entraAdminObjectId
      tenantId: subscription().tenantId
    }
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    licenseType: 'LicenseIncluded'
    pricingModel: pricingModel
    isGeneralPurposeV2: true
    managedInstanceCreateMode: 'Default'
    minimalTlsVersion: '1.2'
    proxyOverride: 'Redirect'
    publicDataEndpointEnabled: true
    requestedBackupStorageRedundancy: 'Local'
    subnetId: subnetId
    timezoneId: 'UTC'
    vCores: 4
    storageSizeInGB: 64
  }
}

output id string = managedInstance.id
output name string = managedInstance.name
output fullyQualifiedDomainName string = managedInstance.properties.fullyQualifiedDomainName
output publicEndpoint string = '${replace(managedInstance.properties.fullyQualifiedDomainName, '${managedInstance.name}.', '${managedInstance.name}.public.')},3342'
