param prefix string
param suffix string
param regionLabel string
param location string
param infrastructureSubnetId string
param logAnalyticsCustomerId string
param containerRegistryLoginServer string
param runtimeIdentityResourceId string
param runtimeIdentityClientId string
param retailDatabaseFqdn string
param retailDatabaseName string = 'eshop'
param keyVaultSecretReferences array = []

@secure()
param logAnalyticsSharedKey string

param containerImage string = 'mcr.microsoft.com/dotnet/samples:aspnetapp'
param tags object = {}

var environmentName = '${prefix}-${regionLabel}-${suffix}-cae'
var appName = '${take(toLower(prefix), 18)}-${suffix}-app'
var retailDatabaseConnectionString = 'Server=tcp:${retailDatabaseFqdn},1433;Initial Catalog=${retailDatabaseName};User Id=${runtimeIdentityClientId};Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
var secretEnvironmentVariables = [
  for secret in keyVaultSecretReferences: {
    name: secret.environmentVariable
    secretRef: secret.name
  }
]
var containerEnvironmentVariables = concat([
  {
    name: 'ASPNETCORE_ENVIRONMENT'
    value: 'Production'
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: runtimeIdentityClientId
  }
  {
    name: 'ConnectionStrings__StoreDbContext'
    value: retailDatabaseConnectionString
  }
], secretEnvironmentVariables)

resource environment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: true
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: true
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentityResourceId}': {}
    }
  }
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: containerRegistryLoginServer
          identity: 'system'
        }
      ]
      secrets: [
        for secret in keyVaultSecretReferences: {
          name: secret.name
          keyVaultUrl: secret.keyVaultUrl
          identity: runtimeIdentityResourceId
        }
      ]
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'placeholder'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: containerEnvironmentVariables
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/'
                port: 8080
              }
              initialDelaySeconds: 1
              periodSeconds: 3
              failureThreshold: 30
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/'
                port: 8080
              }
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/'
                port: 8080
              }
              periodSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 2
        maxReplicas: 10
        rules: [
          {
            name: 'http-concurrency'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

output appFqdn string = app.properties.configuration.ingress.fqdn
output appName string = app.name
output environmentId string = environment.id
output environmentName string = environment.name
output principalId string = app.identity.principalId
