// Linux container Web App — adapted from TravelAPI's appservice.bicep for
// Docker workloads (no WEBSITE_RUN_FROM_PACKAGE; explicit container port).
param location string = resourceGroup().location
param appName string
param serverFarmId string

@description('Full image reference, e.g. ghcr.io/vinirossado/graphexplorer-sync:latest')
param dockerImage string

param dockerRegistryUrl string = 'https://ghcr.io'

@description('Registry username — leave empty for public images')
param dockerRegistryUsername string = ''

@secure()
@description('Registry password/token — leave empty for public images')
param dockerRegistryPassword string = ''

param appSettings array = []

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: serverFarmId
    httpsOnly: true // TLS termination handled by App Service — no plaintext ingress
    siteConfig: {
      linuxFxVersion: 'DOCKER|${dockerImage}'
      alwaysOn: true
      appSettings: concat(
        [
          {
            name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
            value: 'false'
          }
          {
            name: 'WEBSITES_PORT'
            value: '8080' // the Vapor container listens here
          }
          {
            name: 'DOCKER_REGISTRY_SERVER_URL'
            value: dockerRegistryUrl
          }
        ],
        empty(dockerRegistryUsername)
          ? []
          : [
              {
                name: 'DOCKER_REGISTRY_SERVER_USERNAME'
                value: dockerRegistryUsername
              }
              {
                name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
                value: dockerRegistryPassword
              }
            ],
        appSettings
      )
    }
  }
}

output appServiceId string = webApp.id
output principalId string = webApp.identity.principalId
output url string = 'https://${webApp.properties.defaultHostName}'
