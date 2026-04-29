# CLAUDE.md — Salesforce Revenue Cloud Advanced (Native)

## Platform
**Native Revenue Cloud Advanced** — API version 66.0 (Spring '26)
NO managed package namespaces. No `SBQQ__`, no `blng__`.

## Native RCA Object Map

| Old (CPQ/Billing)         | Native RCA Equivalent              |
|---------------------------|------------------------------------|
| `SBQQ__Quote__c`          | `Quote`                            |
| `SBQQ__QuoteLine__c`      | `QuoteLineItem`                    |
| `SBQQ__SubscriptionType__c` | `ProductSellingModel.SellingModelType` |
| `SBQQ__BillingFrequency__c` | `BillingSchedule.BillingFrequency` |
| `blng__Invoice__c`        | `Invoice`                          |
| `blng__BillingSchedule__c`| `BillingSchedule`                  |
| `blng__Payment__c`        | `Payment`                          |
| CPQ Discount Schedule     | `PriceAdjustmentSchedule` + `PriceAdjustmentTier` |

## Key Commands
```bash
sf project deploy start --target-org rca-dev
sf apex run test --target-org rca-dev --wait 10
sf apex run --file scripts/apex/SetupProductCatalog.apex --target-org rca-dev
sf apex run --file scripts/apex/SetupPricingData.apex --target-org rca-dev
sf org assign permset --name RCA_Sales_User --target-org rca-dev
```

## Architecture Rules
- Triggers thin → handler pattern always
- All SOQL uses `WITH SECURITY_ENFORCED`
- All classes use `with sharing`
- Never DML in loops
- Custom exceptions extend `RCAException`
- Pricing logic: use `RevSignaling.PricingProcedureExecutor` — don't reimplement pricing rules in Apex

## Naming
- Apex: `RCA<Feature><Role>.cls` — e.g. `RCAQuoteService`, `RCABillingService`
- LWC: `rca<Feature>` camelCase — e.g. `rcaProductSelector`, `rcaBillingDashboard`
- Tests: append `Test` — e.g. `RCAQuoteServiceTest`

## Orgs
- Dev: `rca-dev`
- Staging: `staging`
- Production: `production`

## GitHub Secrets
- `DEVHUB_SFDX_AUTH_URL`
- `STAGING_SFDX_AUTH_URL`
- `PROD_SFDX_AUTH_URL`
- `SLACK_WEBHOOK_URL`
