targetScope = 'subscription'

@minLength(1)
param environmentName string

param primaryLocation string = 'centralus'
param secondaryLocation string = 'centralus'
param applicationLocation string = 'centralus'

@minLength(3)
@maxLength(18)
param prefix string = 'caldova-lab04'

@allowed([
  'azureSql'
  'sqlMi'
])
param databaseMode string = 'sqlMi'

@allowed([
  'Freemium'
  'Regular'
])
param sqlMiPricingModel string = 'Freemium'

@minLength(1)
param sqlEntraAdminObjectId string = deployer().objectId

@minLength(1)
param sqlEntraAdminLogin string = deployer().userPrincipalName

@secure()
param vmAdminUsername string

@secure()
param vmAdminPassword string

var suffix = take(uniqueString(subscription().id, environmentName, prefix), 8)
var databaseName = 'eshop_ai'
var resourceGroups = {
  bootstrap: 'rg-${prefix}-bootstrap-${suffix}'
  primary: 'rg-${prefix}-primary-${suffix}'
  secondary: 'rg-${prefix}-secondary-${suffix}'
  global: 'rg-${prefix}-global-${suffix}'
}
var tags = {
  Application: 'Caldova'
  Environment: 'Lab'
  ManagedBy: 'azd'
  'azd-env-name': environmentName
}

resource bootstrapResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroups.bootstrap
  location: primaryLocation
  tags: tags
}

resource primaryResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroups.primary
  location: primaryLocation
  tags: tags
}

resource secondaryResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroups.secondary
  location: secondaryLocation
  tags: tags
}

resource globalResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroups.global
  location: primaryLocation
  tags: tags
}

module bootstrap './lab04/complete/bootstrap.bicep' = {
  name: 'bootstrap'
  scope: bootstrapResourceGroup
  params: {
    prefix: prefix
    suffix: suffix
    location: primaryLocation
    keyVaultAdministratorObjectId: sqlEntraAdminObjectId
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
    tags: tags
  }
}

module primary './lab04/complete/primary.bicep' = {
  name: 'primary'
  scope: primaryResourceGroup
  params: {
    prefix: prefix
    suffix: suffix
    location: primaryLocation
    databaseMode: databaseMode
    codeBuildPrincipalId: bootstrap.outputs.codeBuildPrincipalId
    sqlEntraAdminObjectId: sqlEntraAdminObjectId
    sqlEntraAdminLogin: sqlEntraAdminLogin
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
    tags: tags
  }
}

module secondary './lab04/complete/secondary.bicep' = {
  name: 'secondary'
  scope: secondaryResourceGroup
  params: {
    prefix: prefix
    suffix: suffix
    location: secondaryLocation
    applicationLocation: applicationLocation
    databaseMode: databaseMode
    sqlMiPricingModel: sqlMiPricingModel
    codeDeploymentPrincipalId: bootstrap.outputs.codeDeploymentPrincipalId
    containerRegistryName: primary.outputs.containerRegistryName
    containerRegistryLoginServer: primary.outputs.containerRegistryLoginServer
    containerRegistryResourceGroupName: primaryResourceGroup.name
    privateDnsZoneResourceGroupName: primaryResourceGroup.name
    privateDnsZoneName: primary.outputs.privateDnsZoneName
    primaryDatabaseResourceGroupName: primaryResourceGroup.name
    primaryDatabaseVnetName: primary.outputs.databaseVnetName
    primaryDatabaseVnetId: primary.outputs.databaseVnetId
    primaryDatabaseFqdn: primary.outputs.databaseFqdn
    runtimeIdentityResourceId: bootstrap.outputs.runtimeIdentityId
    runtimeIdentityClientId: bootstrap.outputs.runtimeIdentityClientId
    runtimeIdentityPrincipalId: bootstrap.outputs.runtimeIdentityPrincipalId
    sqlEntraAdminObjectId: sqlEntraAdminObjectId
    sqlEntraAdminLogin: sqlEntraAdminLogin
    tags: tags
  }
}

module global './lab04/complete/global.bicep' = {
  name: 'global'
  scope: globalResourceGroup
  params: {
    prefix: prefix
    suffix: suffix
    applicationLocation: applicationLocation
    codeDeploymentPrincipalId: bootstrap.outputs.codeDeploymentPrincipalId
    originFqdn: secondary.outputs.containerAppFqdn
    containerAppsEnvironmentId: secondary.outputs.containerAppsEnvironmentId
    tags: tags
  }
}

output AZURE_RESOURCE_GROUP string = secondaryResourceGroup.name
output LAB04_BOOTSTRAP_RESOURCE_GROUP string = bootstrapResourceGroup.name
output LAB04_PRIMARY_RESOURCE_GROUP string = primaryResourceGroup.name
output LAB04_SECONDARY_RESOURCE_GROUP string = secondaryResourceGroup.name
output LAB04_GLOBAL_RESOURCE_GROUP string = globalResourceGroup.name
output LAB04_PREFIX string = prefix
output LAB04_SUFFIX string = suffix
output LAB04_PRIMARY_LOCATION string = primaryLocation
output LAB04_SECONDARY_LOCATION string = secondaryLocation
output LAB04_APPLICATION_LOCATION string = applicationLocation
output LAB04_SQL_ADMIN_OBJECT_ID string = sqlEntraAdminObjectId
output LAB04_SQL_ADMIN_LOGIN string = sqlEntraAdminLogin
output LAB04_DATABASE_MODE string = databaseMode
output LAB04_SQL_MI_PRICING_MODEL string = sqlMiPricingModel
output LAB04_DATABASE_FQDN string = databaseMode == 'azureSql'
  ? primary.outputs.databaseFqdn
  : secondary.outputs.databaseFqdn
output LAB04_SQL_MI_PUBLIC_ENDPOINT string = databaseMode == 'sqlMi'
  ? secondary.outputs.sqlMiPublicEndpoint
  : ''
output LAB04_DATABASE_NAME string = databaseName
output LAB04_DATABASE_RESOURCE_GROUP string = databaseMode == 'azureSql'
  ? primaryResourceGroup.name
  : secondaryResourceGroup.name
output LAB04_DATABASE_SERVER_NAME string = databaseMode == 'azureSql'
  ? primary.outputs.sqlServerName
  : secondary.outputs.managedInstanceName
output LAB04_SQL_MI_NSG_NAME string = databaseMode == 'sqlMi'
  ? secondary.outputs.sqlMiNetworkSecurityGroupName
  : ''
output LAB04_KEY_VAULT_NAME string = bootstrap.outputs.keyVaultName
output LAB06_BUILD_AZURE_CLIENT_ID string = bootstrap.outputs.codeBuildClientId
output LAB06_BUILD_AZURE_PRINCIPAL_ID string = bootstrap.outputs.codeBuildPrincipalId
output LAB06_BUILD_IDENTITY_NAME string = bootstrap.outputs.codeBuildIdentityName
output LAB06_DEPLOY_AZURE_CLIENT_ID string = bootstrap.outputs.codeDeploymentClientId
output LAB06_DEPLOY_AZURE_PRINCIPAL_ID string = bootstrap.outputs.codeDeploymentPrincipalId
output LAB06_DEPLOYMENT_IDENTITY_NAME string = bootstrap.outputs.codeDeploymentIdentityName
output LAB06_RUNTIME_IDENTITY_NAME string = bootstrap.outputs.runtimeIdentityName
output LAB06_RUNTIME_IDENTITY_RESOURCE_ID string = bootstrap.outputs.runtimeIdentityId
output LAB06_RUNTIME_IDENTITY_CLIENT_ID string = bootstrap.outputs.runtimeIdentityClientId
output LAB06_RUNTIME_IDENTITY_PRINCIPAL_ID string = bootstrap.outputs.runtimeIdentityPrincipalId
output LAB06_CONTAINER_REGISTRY_NAME string = primary.outputs.containerRegistryName
output LAB06_CONTAINER_APP_NAME string = secondary.outputs.containerAppName
output LAB05_RETAIL_DATABASE_NAME string = secondary.outputs.retailDatabaseName
output LAB04_CONTAINER_APPS_ENVIRONMENT_ID string = secondary.outputs.containerAppsEnvironmentId
output FRONT_DOOR_ENDPOINT string = global.outputs.frontDoorEndpointHostName
output FRONT_DOOR_PROFILE_ID string = global.outputs.frontDoorProfileId
output FRONT_DOOR_ORIGIN_ID string = global.outputs.frontDoorOriginId
output FRONT_DOOR_PRIVATE_LINK_REQUEST_MESSAGE string = global.outputs.privateLinkRequestMessage
