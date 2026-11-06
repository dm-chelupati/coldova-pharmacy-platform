# Coldova Pharmacy Operations — Architecture & Dependencies

## Services
| Service | Type | Host | Port | Dependencies |
|---------|------|------|------|--------------|
| frontend | Node.js (Express) | Container App | 3000 | gateway |
| gateway | .NET 8 (ASP.NET) | Container App | 8080 | order-service, payment-service |
| order-service | .NET 8 | Container App | 8080 | PostgreSQL, Service Bus (orders queue) |
| payment-service | .NET 8 | Container App | 8080 | PostgreSQL, benefits-service |
| benefits-service | .NET 8 | Container App | 8080 | authenticated on-premises SQL API |
| worker | .NET 8 | Container App | 8080 | Service Bus (orders queue), PostgreSQL |

## Request Flow
```
User → frontend (App Service)
  → gateway (Container App)
    → order-service → PostgreSQL + Service Bus
    → Review & pay → payment-service → benefits-service
      → HTTPS tunnel → laptop SQL API → SQL Server eligibility + copay
  Worker listens on Service Bus orders queue
```

## Detection and investigation

- SQL Server, Data API Builder, SQL MCP, GitHub MCP, and the authenticated proxy
  run on the laptop.
- Application Insights receives Azure application request telemetry.
- Azure Monitor evaluates prescription payment-processing failures and raises the neutral
  `Caldova Sev2 Alert`.
- The SRE Agent ingests the alert through its native Azure Monitor incident
  platform.
- The response plan routes the incident to an evidence-led custom responder.
- The responder receives assigned Azure CLI, Application Insights, Log
  Analytics, SQL MCP, and GitHub MCP tools. Tool assignment defines what the
  responder can call; server-side tool checks enforce bounded actions. Its
  instructions contain no dependency chain, expected symptom, expected root
  cause, known issue, or prescribed remediation.

## Investigation flow

1. Azure Monitor detects repeated failed `POST /payments/process` requests.
2. The native Azure Monitor incident platform starts the neutral Sev2
   investigation.
3. The response plan hands the incident to `caldova-incident-responder`.
4. The responder uses its assigned MCP tools to discover and correlate evidence.
5. The responder creates or updates a GitHub issue with the evidence-backed RCA.
6. It can request approval to run the bounded
   `terminate_approved_demo_transaction` SQL MCP tool. SQL Server refuses the
   operation unless the exact demo transaction identity, minimum age, expected
   wait state, critical-table lock, and active customer blocking are verified.
   Otherwise, it makes no change and records the recommended human action.
7. The operator can end the demo transaction with
   `onprem-sql/scripts/end-transaction.sh`.

## Autonomous overnight recovery

The separate autonomous scenario uses a dedicated nightly benefits-sync SQL
login and application identity. A stalled sync can block the same customer
payment path, but the autonomous responder receives one additional MCP tool.
That tool has no session-id input and terminates a connection only after SQL
Server verifies the approved identity, minimum transaction age, stalled state,
critical-table lock, active customer blocking, unique match, and overnight UTC
window. Any failed guardrail produces a refusal and no action.
