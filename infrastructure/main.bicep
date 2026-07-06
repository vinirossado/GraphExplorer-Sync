// GraphExplorer-Sync — deploys ONTO the infrastructure TravelAPI already owns
// in this resource group: same App Service Plan, same Key Vault, same
// PostgreSQL flexible server (a new `graphexplorer` database on it). Only the
// container Web App is new, so the incremental cost is ~zero.
//
// Deploy:
//   az deployment group create \
//     --resource-group <travelapi-rg> \
//     --template-file infrastructure/main.bicep \
//     --parameters pgSqlPassword=<admin-password>   # first run only

param location string = resourceGroup().location
var uniqueId = uniqueString(resourceGroup().id)

// Names of the pre-existing resources are deliberately NOT defaulted here —
// this repo is public, and infrastructure names don't belong in it. Pass them
// per deployment (CLI parameters locally, repository secrets in CI).
@description('Name of the existing App Service Plan to deploy onto')
param appServicePlanName string

@description('Name of the existing Key Vault holding the connection secret')
param keyVaultName string

@description('Existing PostgreSQL flexible server (defaults to the sibling-deployment naming convention)')
param postgresServerName string = 'postgresql-${uniqueString(resourceGroup().id)}'

@description('PostgreSQL admin login')
param postgresAdminLogin string

@secure()
@description('PostgreSQL admin password. Required on first deployment to write the connection-string secret; leave empty on redeployments to preserve the existing Key Vault secret.')
param pgSqlPassword string = ''

@description('Container image for the Vapor API')
param dockerImage string = 'ghcr.io/vinirossado/graphexplorer-sync:latest'

@description('GHCR username — only needed while the package is private')
param ghcrUsername string = ''

@secure()
@description('GHCR token (read:packages) — only needed while the package is private')
param ghcrToken string = ''

param globalRateLimit string = '120'
param authRateLimit string = '10'

var connectionSecretName = 'Postgres--GraphExplorerConnectionString'

// ── Existing infrastructure (owned by TravelAPI's deployment) ────────────────

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' existing = {
  name: appServicePlanName
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2025-06-01-preview' existing = {
  name: postgresServerName
}

// ── New: database + connection secret + container app ───────────────────────

resource graphexplorerDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2025-06-01-preview' = {
  parent: postgres
  name: 'graphexplorer'
}

// Same redeploy-safe pattern as TravelAPI: the secret is only (re)written when
// the admin password is explicitly provided.
module connectionSecret 'modules/secrets/keyvault-secret.bicep' = if (!empty(pgSqlPassword)) {
  name: 'graphSyncConnectionStringDeployment'
  params: {
    keyVaultName: keyVaultName
    secretName: connectionSecretName
    // postgres:// URL — exactly the DATABASE_URL format the Vapor app consumes.
    // uriComponent(): passwords with URL-reserved characters (@, :, /, #…)
    // must be percent-encoded or the URL parser mis-splits the authority.
    secretValue: 'postgres://${postgresAdminLogin}:${uriComponent(pgSqlPassword)}@${postgres.name}.postgres.database.azure.com:5432/graphexplorer?sslmode=require'
  }
}

module apiService 'modules/compute/appservice-container.bicep' = {
  name: 'graphSyncApiDeployment'
  params: {
    appName: 'graphsync-${uniqueId}'
    serverFarmId: appServicePlan.id
    location: location
    dockerImage: dockerImage
    dockerRegistryUsername: ghcrUsername
    dockerRegistryPassword: ghcrToken
    appSettings: [
      {
        // Resolved by App Service from Key Vault via the site's managed
        // identity — the connection string never appears in app settings.
        name: 'DATABASE_URL'
        value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=${connectionSecretName})'
      }
      {
        name: 'GLOBAL_RATE_LIMIT'
        value: globalRateLimit
      }
      {
        name: 'AUTH_RATE_LIMIT'
        value: authRateLimit
      }
    ]
  }
  dependsOn: [
    graphexplorerDatabase
  ]
}

// Key Vault Secrets User for the site's managed identity — required for the
// @Microsoft.KeyVault app-setting reference above to resolve.
module keyVaultRoleAssignment 'modules/secrets/key-vault-role.bicep' = {
  name: 'graphSyncKeyVaultRoleDeployment'
  params: {
    keyVaultName: keyVaultName
    principalIds: [
      apiService.outputs.principalId
    ]
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────

output appServiceUrl string = apiService.outputs.url
output appServiceId string = apiService.outputs.appServiceId
output databaseName string = graphexplorerDatabase.name
output connectionSecret string = connectionSecretName
