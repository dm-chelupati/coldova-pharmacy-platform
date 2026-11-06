@description('Azure region for the Application Insights resource.')
param location string

@description('Resource ID of the Caldova Application Insights component.')
param appInsightsResourceId string

resource alertRule 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'caldova-sev2-alert'
  location: location
  kind: 'LogAlert'
  properties: {
    displayName: 'Caldova Sev2 Alert'
    description: 'Caldova Pharmacy customer-impacting service signal.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      appInsightsResourceId
    ]
    targetResourceTypes: [
      'Microsoft.Insights/components'
    ]
    criteria: {
      allOf: [
        {
          query: 'requests | where name == "POST /payments/process" | where success == false'
          timeAggregation: 'Count'
          dimensions: []
          operator: 'GreaterThanOrEqual'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: []
      customProperties: {
        service: 'coldova-pharmacy-payment-prod'
        severity: 'Sev2'
      }
    }
  }
}

output alertRuleId string = alertRule.id
