# Contoso Trading

Multi-service order processing platform for testing Azure SRE Agent. Deploys 5 services with a database, message queue, and monitoring — then break things and see if the agent can diagnose them.

Supports two deployment modes: **standard** (public endpoints) and **VNet-integrated** (private, network-isolated).

## Architecture

### Standard Mode (`enableVnet=false`)

All services have public endpoints. Simple to deploy and test.

```
                    ┌─────────────────────────────────────────────┐
                    │              Azure Resource Group            │
                    │                                             │
  Internet ───────►│  Frontend ──► Gateway ──► Order Service      │
                    │  (Container   (Container   (Container       │
                    │   App)         App)         App)            │
                    │                  │                          │
                    │                  ├──► Payment Service       │
                    │                  │    (Container App)       │
                    │                  │                          │
                    │                  └──► Service Bus ──► Worker│
                    │                                    (Cont.App)│
                    │                                             │
                    │              PostgreSQL                     │
                    │         (public access)                     │
                    │                                             │
                    │    Log Analytics + App Insights             │
                    └─────────────────────────────────────────────┘
```

### VNet-Integrated Mode (`enableVnet=true`, default)

All services are inside a Virtual Network with no public endpoints. Azure Firewall controls egress traffic. Only reachable from within the VNet (e.g., by SRE Agent with VNet connection).

```
                    ┌─────────────────────────────────────────────────────┐
                    │                   Virtual Network (10.0.0.0/16)     │
                    │                                                     │
                    │  ┌──────────────────────────────────────────┐       │
                    │  │ snet-cae (10.0.0.0/21)                   │       │
                    │  │  Container Apps Environment (internal)   │       │
                    │  │                                          │       │
                    │  │  Frontend ──► Gateway ──► Order Service  │       │
                    │  │                  ├──► Payment Service    │       │
                    │  │                  └──► Service Bus ──► Worker     │
                    │  └──────────────────────────────────────────┘       │
                    │                                                     │
                    │  ┌─────────────────────┐  ┌──────────────────┐     │
                    │  │ snet-pe             │  │ AzureFirewall    │     │
                    │  │ (10.0.10.0/24)      │  │ Subnet           │     │
                    │  │  PostgreSQL PE ─────┼──┤ (10.0.11.0/26)  │     │
                    │  │  (private endpoint, │  │                  │     │
                    │  │   10.0.10.4)        │  │  ┌────────────┐  │     │
                    │  └─────────────────────┘  │  │ Azure      │  │     │
                    │                            │  │ Firewall   │──┼──►Internet
                    │  ┌─────────────────────┐  │  │ (egress    │  │  (filtered)
                    │  │ snet-sre-agent      │  │  │  control)  │  │     │
                    │  │ (10.0.12.0/28)      │  │  └────────────┘  │     │
                    │  │  SRE Agent ─────────┼──┘                  │     │
                    │  └─────────────────────┘  └──────────────────┘     │
                    │                                                     │
                    │  ┌─────────────────────────────────────────┐       │
                    │  │  Private DNS Zones                       │       │
                    │  │  *.thankful...azurecontainerapps.io      │       │
                    │  │  privatelink.postgres.database.azure.com │       │
                    │  └─────────────────────────────────────────┘       │
                    │                                                     │
                    │    Log Analytics + App Insights (public data plane) │
                    └─────────────────────────────────────────────────────┘
```

### VNet Subnets

| Subnet | CIDR | Purpose | Delegation |
|--------|------|---------|------------|
| `snet-cae` | 10.0.0.0/21 | Container Apps Environment (all 5 services) | — |
| `snet-pe` | 10.0.10.0/24 | Private Endpoints (PostgreSQL) | — |
| `AzureFirewallSubnet` | 10.0.11.0/26 | Azure Firewall | — (Azure-required name) |
| `snet-sre-agent` | 10.0.12.0/28 | SRE Agent VNet connection | `Microsoft.App/environments` |

### PostgreSQL Networking — Why Private Endpoint?

PostgreSQL Flexible Server supports two mutually exclusive networking modes:

1. **Delegated subnet** (VNet integration) — the server gets a private IP in a delegated subnet. However, Azure-managed networking for delegated subnets **restricts traffic to subnets deployed alongside the server**. Other delegated subnets (like the SRE Agent's `snet-sre-agent`) cannot reach it, even within the same VNet.

2. **Private endpoint** — the server gets a NIC in a regular (non-delegated) subnet. Standard VNet routing applies, so **any subnet in the VNet can reach it**.

We use **private endpoint** (option 2) so that both the container apps in `snet-cae` and the SRE Agent in `snet-sre-agent` can connect to PostgreSQL. The private endpoint lives in `snet-pe` (10.0.10.0/24) with a `privatelink.postgres.database.azure.com` DNS zone that resolves the server FQDN to the PE's private IP.

### Azure Firewall

When VNet is enabled, Azure Firewall provides:

- **Egress filtering** — internal services have no public IPs but need outbound access to pull container images (ACR/MCR), send telemetry (Azure Monitor), and reach Azure management APIs
- **Single egress IP** — all outbound traffic exits through the firewall's public IP, giving a known static IP for allowlisting and audit
- **Network rules** — allow outbound from 10.0.0.0/16 to required Azure services
- **Application rules** — allow FQDNs for ACR, MCR, Azure Monitor, Container Apps management

### Control Plane vs Data Plane

| Access Type | Without VNet Connection | With VNet Connection |
|-------------|------------------------|---------------------|
| `az containerapp list` (control plane) | Works | Works |
| `az containerapp restart` (control plane) | Works | Works |
| `curl frontend/health` (data plane) | **Blocked** — DNS won't resolve | Works |
| `psql pg-*` (data plane) | **Blocked** — private endpoint only | Works (via PE in snet-pe) |
| App Insights queries (data plane) | Works (public API) | Works |

## Services

| Service | Type | Role |
|---------|------|------|
| Frontend | Container App (Node.js) | User-facing web UI, routes to gateway |
| Gateway | Container App (.NET) | Routes requests to backend services |
| Order Service | Container App (.NET) | Creates orders, publishes to queue |
| Payment Service | Container App (.NET) | Processes payments |
| Worker | Container App (.NET) | Consumes queue, completes orders |
| Database | PostgreSQL Flexible Server | Shared order + payment data |
| Service Bus | Standard tier | Async order processing pipeline |
| Monitoring | Log Analytics + App Insights | Telemetry from all services |

## Deploy

### Standard (public endpoints)

```bash
azd up
# When prompted, set enableVnet=false
```

Or set it via environment variable:

```bash
azd env set enableVnet false
azd up
```

### VNet-Integrated (default)

```bash
azd up
```

After deployment, create the private DNS zone and SRE Agent subnet:

```bash
# Get CAE domain and static IP
CAE_DOMAIN=$(az containerapp env show -n env-<suffix> -g <rg> --query properties.defaultDomain -o tsv)
CAE_IP=$(az containerapp env show -n env-<suffix> -g <rg> --query properties.staticIp -o tsv)

# Create private DNS zone + wildcard record + VNet link
az network private-dns zone create -g <rg> -n $CAE_DOMAIN
az network private-dns record-set a add-record -g <rg> -z $CAE_DOMAIN -n "*" -a $CAE_IP
VNET_ID=$(az network vnet show -g <rg> -n vnet-<suffix> --query id -o tsv)
az network private-dns link vnet create -g <rg> -z $CAE_DOMAIN -n cae-dns-link -v $VNET_ID -e false

# Create subnet for SRE Agent VNet connection
az network vnet subnet create -g <rg> --vnet-name vnet-<suffix> \
  -n snet-sre-agent --address-prefix 10.0.12.0/28 \
  --delegations Microsoft.App/environments
```

Then in the SRE Agent portal, connect to the VNet using `snet-sre-agent`.
