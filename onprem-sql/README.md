# Caldova simulated on-prem SQL Server

This lab runs SQL Server on the presenter's laptop to represent Caldova's
on-premises benefits system. The customer application remains in Azure.

## Trust boundary

- SQL Server binds only to `127.0.0.1:1433`.
- SQL credentials live in the gitignored `.env` file.
- The Azure application reaches the local SQL API through an outbound HTTPS
  tunnel from the laptop. SQL Server remains bound to `127.0.0.1:1433`.
- The application login can only read the two application tables.
- The transaction-holder login can update only `dbo.MemberBenefits`.
- The nightly-sync login can update only `dbo.MemberBenefits`.
- The SRE reader can inspect blocking state but cannot terminate sessions.
- SQL Server MCP uses the SRE reader and exposes only configured read entities.
- A separate automation MCP identity has server connection-termination permission,
  but its endpoint exposes only one stored procedure with server-enforced
  identity, age, blocking, table-lock, uniqueness, and time-window guardrails.
- GitHub MCP exposes only the issue toolset through the authenticated proxy.

## Start the database

```bash
./scripts/start-onprem.sh
```

The script creates strong local secrets, starts SQL Server, creates
`CaldovaBenefits`, seeds member and catalog records, and starts the SQL and
GitHub MCP services. Set `GITHUB_PERSONAL_ACCESS_TOKEN` in the generated
gitignored `.env` file before the first start.

Start the outbound HTTPS endpoint in a second terminal:

```bash
./scripts/start-tunnels.sh
```

## Run the transaction scenario

```bash
./scripts/begin-transaction.sh
./scripts/generate-application-traffic.sh
./scripts/observe-transaction.sh
```

The traffic script calls the payment route so Application Insights records the
customer-facing failures. Azure Monitor raises the neutral `Caldova Sev2 Alert`
and the SRE Agent ingests it through the native Azure Monitor incident platform.

After the investigation, the responder can request approval to run the bounded
`terminate_approved_demo_transaction` SQL MCP tool. SQL Server executes it only
when the exact demo transaction is old enough, still in its expected observation
wait, locking `MemberBenefits`, and actively blocking a customer payment query.
The operator can also end the transaction manually:

```bash
./scripts/end-transaction.sh
```

SQL Server rolls back the uncommitted change and releases the lock. The payment
route should return to HTTP 200 without restarting the Azure application.

## Run the autonomous nightly-sync scenario

The second scenario represents a nightly insurer synchronization job that
updates member eligibility and stalls before commit while its connection
remains open:

```bash
./scripts/begin-nightly-sync.sh
./scripts/generate-application-traffic.sh
```

The `terminate_stalled_benefits_sync` MCP tool cannot accept a session ID and
cannot terminate arbitrary SQL sessions. SQL Server performs every guardrail
check before terminating the single approved stalled job session. If any check
fails, the tool returns `refused` without changing the database.

Use the manual cleanup only if a test is interrupted before autonomous recovery:

```bash
./scripts/end-nightly-sync.sh
```
