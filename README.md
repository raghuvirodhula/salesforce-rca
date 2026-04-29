# Salesforce Revenue Cloud Advanced (Native)

A Salesforce DX project built on **native Revenue Cloud Advanced** — no managed packages, no `SBQQ__` or `blng__` namespaces. Uses the standard Salesforce object model introduced for Revenue Lifecycle Management (RLM).

> **API Version:** 66.0 (Spring '26)  
> **Platform:** Revenue Cloud Advanced — natively built on Agentforce 360 Platform

---

## 📦 Project Structure

```
salesforce-rca/
├── force-app/main/default/
│   ├── classes/                    # Apex service, handler, batch classes
│   ├── triggers/                   # Thin triggers on native RCA objects
│   ├── lwc/                        # Lightning Web Components
│   │   ├── rcaProductSelector/     # Product catalog browsing & selection
│   │   ├── rcaQuoteApproval/       # Quote approval submission UI
│   │   └── rcaBillingDashboard/    # Invoice & billing schedule dashboard
│   ├── flows/                      # Salesforce Flows for pricing & approvals
│   ├── permissionsets/             # RCA permission sets
│   └── customMetadata/             # Config-driven settings
├── scripts/apex/                   # Anon Apex data setup scripts
├── config/                         # Scratch org definition
├── .github/workflows/              # CI/CD pipelines
└── docs/                           # Architecture & data model docs
```

---

## 🗂️ Native RCA Object Model

Revenue Cloud Advanced uses **standard Salesforce objects** — no managed package namespaces needed.

| Domain                  | Key Objects                                                                 |
|-------------------------|-----------------------------------------------------------------------------|
| **Product Catalog**     | `Product2`, `ProductCategory`, `ProductCatalog`, `ProductSellingModel`, `ProductSellingModelOption` |
| **Pricing**             | `PriceBook2`, `PricebookEntry`, `PriceAdjustmentSchedule`, `PriceAdjustmentTier`, `ProductSellingModel` |
| **Quoting (Transaction Management)** | `Quote`, `QuoteLineItem`, `Opportunity`, `OpportunityLineItem` |
| **Orders**              | `Order`, `OrderItem`                                                        |
| **Contracts**           | `Contract`, `ContractLineItem`, `AssetAction`, `Asset`                      |
| **Billing**             | `BillingSchedule`, `BillingScheduleGroup`, `Invoice`, `InvoiceLine`, `CreditMemo` |
| **Usage**               | `UsageSummary`, `UsageRecord`, `RatingRequest`                              |
| **Orchestration**       | `OrderDeliveryGroup`, `FulfillmentOrder`, `FulfillmentOrderLineItem`        |

---

## 🚀 Getting Started

### Prerequisites
- Salesforce CLI (`sf`) v2+
- VS Code with Salesforce Extension Pack
- Revenue Cloud Advanced licence provisioned in your org

### Setup

```bash
# 1. Clone
git clone https://github.com/your-org/salesforce-rca.git
cd salesforce-rca

# 2. Auth (scratch org via DevHub, or sandbox)
sf org login web --alias rca-dev --set-default

# 3. Deploy
sf project deploy start --target-org rca-dev

# 4. Seed sample data
sf apex run --file scripts/apex/SetupProductCatalog.apex --target-org rca-dev
sf apex run --file scripts/apex/SetupPricingData.apex --target-org rca-dev

# 5. Assign permissions
sf org assign permset --name RCA_Sales_User --target-org rca-dev
```

### Running Tests

```bash
sf apex run test \
  --target-org rca-dev \
  --result-format human \
  --wait 15
```

---

## 🔄 CI/CD

| Workflow              | Trigger                  | Target          |
|-----------------------|--------------------------|-----------------|
| `validate-pr.yml`     | PR → `develop`           | Scratch Org     |
| `deploy-staging.yml`  | Merge → `develop`        | Staging Sandbox |
| `deploy-prod.yml`     | Merge → `main`           | Production      |

---

## 🌿 Branching

```
main        →  Production
develop     →  Staging/UAT
feature/*   →  Feature development
hotfix/*    →  Emergency fixes
```

---

## 📐 Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full native RCA data flow and object relationships.
