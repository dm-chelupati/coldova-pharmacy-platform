@description('Azure region for the Application Insights resource.')
param location string

@description('Resource ID of the Caldova Application Insights component.')
param appInsightsResourceId string

@description('Whether the autonomous demonstration alert is enabled.')
param enabled bool = false

resource alertRule 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'caldova-autonomous-sev2-alert-demo'
  location: location
  kind: 'LogAlert'
  properties: {
    displayName: 'Caldova Autonomous Sev2 Alert'
    description: 'Caldova Pharmacy sustained customer-impacting service signal.'
    severity: 2
    enabled: enabled
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    scopes: [
      appInsightsResourceId
    ]
    targetResourceTypes: [
      'Microsoft.Insights/components'
    ]
    criteria: {
      allOf: [
        {
          query: 'requests | where name == "POST /payments/process" | summarize FailedCount = countif(success == false) by bin(timestamp, 1m)'
          timeAggregation: 'Maximum'
          metricMeasureColumn: 'FailedCount'
          dimensions: []
          operator: 'GreaterThanOrEqual'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 3
            minFailingPeriodsToAlert: 3
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
