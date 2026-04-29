# Architecture — Native Revenue Cloud Advanced

## Revenue Lifecycle Flow

```
Opportunity
    └─► Quote  ──────────────────────────────────────────────────────────────────┐
         │  QuoteLineItem (ProductSellingModel → defines billing motion)          │
         │  ↓ Pricing Engine (RevSignaling / PricingRecipe)                       │
         │  ↓ Approval Orchestration (Flow Orchestration)                         │
         ▼                                                                        │
        Order ◄──────────────────────────────────────────────────────────────────┘
         │  OrderItem (ProductSellingModelId)
         │  ↓ Activate
         ▼
    BillingSchedule (auto-created per OrderItem by platform)
         │
         ├── [Subscription] Recurring → Invoice → InvoiceLine
         ├── [Usage]        UsageSummary → RatingRequest → BillingSchedule → Invoice
         └── [One-Time]     Single Invoice on activation
         ↓
       Invoice → Posted → Payment
         └──► CreditMemo (if adjustment needed)
         ↓
       Asset (created/updated by Dynamic Revenue Orchestrator)
         └──► AssetAction (Amend / Renew / Cancel)
         ↓
       Contract / ContractLineItem (committed terms)
```

## Native Object Reference (No Namespace)

### Product Catalog
| Object | Purpose |
|--------|---------|
| `Product2` | Core product record |
| `ProductCatalog` | Groups products into a catalog |
| `ProductCategory` | Hierarchical grouping within a catalog |
| `ProductSellingModel` | Selling motion — `OneTime`, `TermedSubscription`, `EvergreenSubscription` |
| `ProductSellingModelOption` | Join: links Product2 ↔ ProductSellingModel |

### Pricing
| Object | Purpose |
|--------|---------|
| `Pricebook2` / `PricebookEntry` | Standard list pricing |
| `PriceAdjustmentSchedule` | Volume / tiered discount schedule |
| `PriceAdjustmentTier` | Individual tier in a schedule |
| `PricingRecipe` | Metadata config for the pricing engine |
| `RevSignaling` namespace | Apex entry point to run pricing procedures |

### Quoting (Transaction Management)
| Object | Purpose |
|--------|---------|
| `Quote` | Quote header |
| `QuoteLineItem` | Line with `ProductSellingModelId` field |

### Orders
| Object | Purpose |
|--------|---------|
| `Order` | Order header |
| `OrderItem` | Line with `ProductSellingModelId` |

### Billing
| Object | Purpose |
|--------|---------|
| `BillingSchedule` | Per-OrderItem invoicing schedule |
| `BillingScheduleGroup` | Groups related schedules |
| `Invoice` | Invoice header |
| `InvoiceLine` | Individual invoice line |
| `CreditMemo` | Credit / adjustment against a posted invoice |
| `Payment` | Payment applied to an invoice |

### Usage
| Object | Purpose |
|--------|---------|
| `UsageSummary` | Aggregated consumption per billing period |
| `UsageRecord` | Raw event / usage data |
| `RatingRequest` | Trigger to rate usage against a rate card |
| `RateCard` / `RateCardEntry` | Usage pricing tiers |

### Assets & Contracts
| Object | Purpose |
|--------|---------|
| `Asset` | What the customer owns / is subscribed to |
| `AssetAction` | Amendment, renewal, cancellation events |
| `Contract` | Legal agreement header |
| `ContractLineItem` | Committed product within a contract |

## Key Design Decisions

1. **No Apex pricing logic** — use the native `RevSignaling.PricingProcedureExecutor` so pricing stays in the data model (PricingRecipe), not in code.
2. **BillingSchedule is platform-managed** — created automatically on Order activation based on ProductSellingModel; only query / advance it in Apex.
3. **AssetAction for amendments** — never create a new Order for mid-term changes; use `AssetAction` so the platform handles proration via the configured ProrationPolicy.
4. **Flow Orchestration for approvals** — use native Flow Orchestration (not Process Builder or legacy Approval Processes) for quote approval routing.
