param location string
param suffix string
param tags object
param envId string
param acrServer string
param acrName string
@secure()
param acrPassword string
param aiConnStr string
param onPremSqlApiUrl string
@secure()
param onPremSqlApiToken string
param dtEnvVars array = []
param dtSecrets array = []

var sqlApiSecrets = [
  {
    name: 'onprem-sql-api-token'
    value: onPremSqlApiToken
  }
]

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'benefits-svc-${suffix}'
  location: location
  tags: union(tags, { 'azd-service-name': 'benefits-service' })
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: envId
    configuration: {
      secrets: concat([
        { name: 'acr-password', value: acrPassword }
      ], sqlApiSecrets, dtSecrets)
      registries: [
        { server: acrServer, username: acrName, passwordSecretRef: 'acr-password' }
      ]
      ingress: { external: false, targetPort: 8080 }
    }
    template: {
      containers: [
        {
          name: 'benefits-service'
          image: 'mcr.microsoft.com/dotnet/samples:aspnetapp'
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: concat([
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aiConnStr }
            { name: 'ONPREM_SQL_API_URL', value: onPremSqlApiUrl }
            { name: 'ONPREM_SQL_API_TOKEN', secretRef: 'onprem-sql-api-token' }
            { name: 'ONPREM_SQL_API_TIMEOUT_SECONDS', value: '5' }
          ], dtEnvVars)
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

output url string = 'https://${app.properties.configuration.ingress.fqdn}'
