targetScope = 'subscription'

@description('Environment name')
param environmentName string

@description('Primary location')
param location string = 'westus2'

@description('Enable Dynatrace OneAgent auto-instrumentation on Container Apps')
param enableDynatrace bool = false

@description('Dynatrace environment URL (e.g. https://abc12345.live.dynatrace.com)')
param dtEnvironmentUrl string = ''

@description('Dynatrace API token (needs openTelemetryTrace.ingest + metrics.ingest + logs.ingest scopes)')
@secure()
param dtApiToken string = ''

@description('Enable VNet integration for all services')
param enableVnet bool = true

@description('HTTPS endpoint for the on-premises SQL API.')
param onPremSqlApiUrl string

@description('Bearer token for the on-premises SQL API.')
@secure()
param onPremSqlApiToken string

var tags = { 'azd-env-name': environmentName }
var rgName = 'rg-${environmentName}'
var suffix = uniqueString(subscription().subscriptionId, rgName)

// Dynatrace OTLP env vars — injected into every Container App when enabled
var dtEnvVars = enableDynatrace ? [
  { name: 'DT_OTLP_ENDPOINT', value: '${dtEnvironmentUrl}/api/v2/otlp' }
  { name: 'DT_OTLP_TOKEN', secretRef: 'dt-api-token' }
] : []
var dtSecrets = enableDynatrace ? [
  { name: 'dt-api-token', value: dtApiToken }
] : []

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: location
  tags: tags
}

// ── Virtual Network ──

module vnet 'modules/vnet.bicep' = if (enableVnet) {
  name: 'vnet'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags }
}

// ── Azure Firewall ──

module firewall 'modules/firewall.bicep' = if (enableVnet) {
  name: 'firewall'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    firewallSubnetId: vnet.outputs.firewallSubnetId
  }
}

// ── Monitoring (all services log here) ──

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags }
}

// ── Container Registry ──

module registry 'modules/registry.bicep' = {
  name: 'registry'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags }
}

// ── Service Bus (order → payment → worker async pipeline) ──

module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags }
}

// ── Database (shared PostgreSQL) ──

module database 'modules/database.bicep' = {
  name: 'database'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags
    peSubnetId: enableVnet ? vnet.outputs.peSubnetId : ''
    vnetId: enableVnet ? vnet.outputs.vnetId : '' }
}

// ── Container App Environment (shared by all backend services) ──

module containerEnv 'modules/container-env.bicep' = {
  name: 'container-env'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags
    lawClientId: monitoring.outputs.lawClientId
    lawClientKey: monitoring.outputs.lawClientKey
    caeSubnetId: enableVnet ? vnet.outputs.caeSubnetId : '' }
}

// ── Benefits Service (Container App — hybrid SQL Server dependency) ──

module benefitsService 'modules/benefits-service.bicep' = {
  name: 'benefits-service'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    onPremSqlApiUrl: onPremSqlApiUrl
    onPremSqlApiToken: onPremSqlApiToken
    dtEnvVars: dtEnvVars
    dtSecrets: dtSecrets
  }
}

// ── Frontend (Container App — user-facing web UI) ──

module frontend 'modules/frontend.bicep' = {
  name: 'frontend'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    apiUrl: gateway.outputs.url
    dtOtlpEndpoint: enableDynatrace ? '${dtEnvironmentUrl}/api/v2/otlp' : ''
    dtOtlpToken: enableDynatrace ? dtApiToken : ''
  }
}

// ── Gateway (Container App — routes to backend services) ──

module gateway 'modules/gateway.bicep' = {
  name: 'gateway'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    orderServiceUrl: orderService.outputs.url
    paymentServiceUrl: paymentService.outputs.url
    benefitsServiceUrl: benefitsService.outputs.url
    dtEnvVars: dtEnvVars
    dtSecrets: dtSecrets
  }
}

// ── Order Service (Container App — creates orders, publishes to queue) ──

module orderService 'modules/order-service.bicep' = {
  name: 'order-service'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    dbConnStr: database.outputs.connStr
    sbName: serviceBus.outputs.sbName
    dtEnvVars: dtEnvVars
    dtSecrets: dtSecrets
  }
}

// ── Payment Service (Container App — processes payments) ──

module paymentService 'modules/payment-service.bicep' = {
  name: 'payment-service'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    dbConnStr: database.outputs.connStr
    benefitsServiceUrl: benefitsService.outputs.url
    dtEnvVars: dtEnvVars
    dtSecrets: dtSecrets
  }
}

// ── Worker (Container App — processes queue messages, completes orders) ──

module worker 'modules/worker-service.bicep' = {
  name: 'worker'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    dbConnStr: database.outputs.connStr
    sbName: serviceBus.outputs.sbName
    dtEnvVars: dtEnvVars
    dtSecrets: dtSecrets
  }
}

// ── Outputs ──

output RESOURCE_GROUP string = rg.name
output FRONTEND_URL string = frontend.outputs.url
output GATEWAY_URL string = gateway.outputs.url
output BENEFITS_SERVICE_URL string = benefitsService.outputs.url
output AI_NAME string = monitoring.outputs.aiName
output ACR_NAME string = registry.outputs.acrName
output ACR_LOGIN_SERVER string = registry.outputs.acrLoginServer
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.acrLoginServer
output VNET_ID string = enableVnet ? vnet.outputs.vnetId : ''
output VNET_NAME string = enableVnet ? vnet.outputs.vnetName : ''
output FIREWALL_NAME string = enableVnet ? firewall.outputs.firewallName : ''
output FIREWALL_PRIVATE_IP string = enableVnet ? firewall.outputs.firewallPrivateIp : ''
output FIREWALL_PUBLIC_IP string = enableVnet ? firewall.outputs.firewallPublicIp : ''
