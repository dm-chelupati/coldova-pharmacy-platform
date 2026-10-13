# Contoso Trading — Architecture & Dependencies

## Services
| Service | Type | Host | Port | Dependencies |
|---------|------|------|------|--------------|
| frontend | Node.js (Express) | App Service | 3000 | gateway |
| gateway | .NET 8 (ASP.NET) | Container App | 8080 | order-service, payment-service |
| order-service | .NET 8 | Container App | 8080 | PostgreSQL, Service Bus (orders queue) |
| payment-service | .NET 8 | Container App | 8080 | PostgreSQL |
| worker | .NET 8 | Container App | 8080 | Service Bus (orders queue), PostgreSQL |

## Request Flow
```
User → frontend (App Service)
  → gateway (Container App)
    → order-service → PostgreSQL + Service Bus
    → payment-service → PostgreSQL
  Worker listens on Service Bus orders queue
```

## Observability
- **Primary**: Dynatrace (all 5 services export traces + metrics + logs via OTLP)
- **Secondary**: Azure App Insights + Log Analytics Workspace
- Dynatrace environment: configured via DT_OTLP_ENDPOINT env var on each service

## Common Failure Modes

### 5xx Errors
- **Database connection failures**: PostgreSQL connection pool exhaustion under load. Check `DATABASE_URL` connectivity and connection count.
- **Service Bus failures**: If worker can't connect to Service Bus, orders queue up. Check SERVICEBUS_CONNECTION env var.
- **OOM kills**: Container Apps have memory limits. Check restart count and memory metrics.

### 4xx Errors
- **404 on gateway root path**: Normal — Container App ingress health probes hit `/` which has no handler. Ignore.
- **404 on API endpoints**: Check if service is actually deployed (not placeholder image).
- **403 on frontend**: publicNetworkAccess may be disabled on App Service. Check with `az webapp show`.

## Handling Preferences
- **Confirm before acting**: Always verify error rates are sustained (>1 minute) before declaring an incident.
- **Use Dynatrace first**: Query Dynatrace MCP for distributed traces showing the error. This gives the full request path.
- **Correlate with deployments**: Check `az containerapp revision list` for recent revisions and their creation times.
- **Source code analysis**: If the trace points to a specific endpoint, examine the source code for that handler in the GitHub repo.
- **Mitigation in Azure**: For deployment issues, suggest rollback via `az containerapp revision activate`. For config issues, suggest `az containerapp update` with corrected env vars.
