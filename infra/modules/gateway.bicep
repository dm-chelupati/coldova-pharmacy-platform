param location string
param suffix string
param tags object
param envId string
param acrServer string
param acrName string
@secure()
param acrPassword string
param aiConnStr string
param orderServiceUrl string
param paymentServiceUrl string
param benefitsServiceUrl string
param dtEnvVars array = []
param dtSecrets array = []

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'gateway-${suffix}'
  location: location
  tags: union(tags, { 'azd-service-name': 'gateway' })
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: envId
    configuration: {
      secrets: concat([
        { name: 'acr-password', value: acrPassword }
      ], dtSecrets)
      registries: [
        { server: acrServer, username: acrName, passwordSecretRef: 'acr-password' }
      ]
      ingress: { external: true, targetPort: 8080 }
    }
    template: {
      containers: [
        {
          name: 'gateway'
          image: 'mcr.microsoft.com/dotnet/samples:aspnetapp'
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: concat([
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aiConnStr }
            { name: 'ORDER_SERVICE_URL', value: orderServiceUrl }
            { name: 'PAYMENT_SERVICE_URL', value: paymentServiceUrl }
            { name: 'BENEFITS_SERVICE_URL', value: benefitsServiceUrl }
          ], dtEnvVars)
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

output url string = 'https://${app.properties.configuration.ingress.fqdn}'
