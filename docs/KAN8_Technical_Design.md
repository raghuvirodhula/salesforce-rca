# KAN-8 — Technical Design: BB1 Bulk Billing Product & Ramp Pricing

| Field          | Value                                                              |
|----------------|--------------------------------------------------------------------|
| Story          | [KAN-8](../scripts/jira_client.py) — Define BB1 bulk billing product and ramp pricing |
| Branch         | `feat/KAN-3-bulk-billing-ramp-pricing`                              |
| Salesforce API | 66.0 (Spring '26) — Native Revenue Cloud Advanced                   |
| Author         | Raghu Virodhula                                                    |
| Date           | 2026-05-12                                                          |

---

## 1. Executive Summary

KAN-8 establishes **BB1** as the canonical bulk-billing product and codifies its ramp
pricing schedule (Year 1 = 20% off, Year 2 = 10% off, Year 3+ = list).
The ramp values live in **Custom Metadata**, not in Apex, so Finance can
re-tune the schedule without code changes. A single **service-class entry
point** (`RCABulkBillingService`) feeds three consumers:

- **Order Orchestration** (Flow `@InvocableMethod`)
- **Zuora consolidated billing** (platform event `BulkBilling_Orchestration__e`)
- **Internal CRM UI** (LWC `rcaBulkBillingRampViewer`)

This refactor supersedes the throwaway `BulkBillingService` proved out in KAN-3.

## 2. Acceptance-Criteria Mapping

| AC from KAN-8                                                          | Implementation                                                                 |
|------------------------------------------------------------------------|--------------------------------------------------------------------------------|
| BB1 is defined as a bulk-billing product                               | `BulkBillingRampSetting__mdt` rows keyed by `ProductCode__c = 'BB1'`. Constant `RCABulkBillingService.PRODUCT_CODE_BB1`. |
| Year 1 = 20%, Year 2 = 10%, Year 3+ = standard                         | Three seeded `BulkBillingRampSetting.*.md-meta.xml` records. Year 3 row has discount = 0 to make "no discount" explicit and audited. |
| Metadata available for orchestration and Zuora billing                 | `BulkBilling_Orchestration__e` platform event carries `RampPayloadJson__c` (the full envelope) and key indices for routing. |

## 3. Component Inventory

### Data model
| Component                                | Type             | Status   |
|------------------------------------------|------------------|----------|
| `BulkBillingRampSetting__mdt`            | Custom Metadata  | Updated  |
| ↳ `ProductCode__c`, `IsActive__c`, `EffectiveFromDate__c` | Fields | Added    |
| `BulkBilling_Orchestration__e`           | Platform Event   | New      |

### Apex
| Class                                  | Role                                                       |
|----------------------------------------|------------------------------------------------------------|
| `RCABulkBillingService`                | Public service: discounts, envelope, publish, Flow + LWC.  |
| `RCABulkBillingRampSettingSelector`    | Cached metadata reader, test-injectable.                   |
| `RCABulkBillingPayload`                | DTO (`Envelope`, `RampTier`); JSON-serializable.           |
| `RCABulkBillingServiceTest`            | Unit + bulk + governor + edge-case coverage (≥85%).        |
| `RCAException`                         | Reused; common RCA error type.                             |
| ~~`BulkBillingService`~~ / ~~`...Test`~~ | **Retired** (destructiveChanges.xml).                    |

### LWC
| Component                              | Role                                                     |
|----------------------------------------|----------------------------------------------------------|
| `rcaBulkBillingRampViewer`             | App/Record-page panel: live preview of the ramp + TCV.  |

### Permission set
| Object / Class                                          | Access  |
|---------------------------------------------------------|---------|
| `RCABulkBillingService`, `RCABulkBillingPayload`, `RCABulkBillingRampSettingSelector` | Enabled |

## 4. Architecture & Flow

```
Sales / Service Cloud (record page)
        │
        │  LWC rcaBulkBillingRampViewer (@AuraEnabled, cacheable=true)
        ▼
┌──────────────────────────────────────────────────────────────────┐
│                  RCABulkBillingService                           │
│  - getDiscountPercentage(productCode, year)                      │
│  - buildEnvelope(...)                                            │
│  - publishOrchestrationEvents(...)                               │
│  - previewRamp(...)         (@AuraEnabled)                       │
│  - applyRampPricing(...)    (@InvocableMethod)                   │
└──────────────────────────────────────────────────────────────────┘
        │                            │                          │
        ▼                            ▼                          ▼
RCABulkBillingRampSettingSelector  RCABulkBillingPayload  EventBus.publish
        │                                                       │
        ▼                                                       ▼
BulkBillingRampSetting__mdt                  BulkBilling_Orchestration__e
                                                               │
                                                               ▼
                                            Order Orchestration  +  Zuora
                                            (downstream consumers)
```

## 5. Pricing math (single source of truth)

For each contract year `y ∈ [1, termYears]`:

```
discount(y)   = metadata row matching (productCode, y).DiscountPercentage__c, else 0
netAnnual(y)  = ROUND(baseAnnualPrice × (100 − discount(y)) / 100, 2)
TCV           = Σ netAnnual(y), rounded to 2 dp
periodStart(y)= contractStartDate + (y − 1) years
periodEnd(y)  = contractStartDate +  y      years − 1 day
```

Rounding: `System.RoundingMode.HALF_UP` for currency consistency with Zuora.
Term cap: 30 years (hard-coded to bound governor exposure; rejected with `RCAException`).

## 6. SOQL & Governor budget

The selector issues **one** query per transaction:

```apex
SELECT ProductCode__c, YearNumber__c, DiscountPercentage__c,
       IsActive__c, EffectiveFromDate__c
FROM   BulkBillingRampSetting__mdt
WHERE  IsActive__c = true
ORDER  BY ProductCode__c ASC, YearNumber__c ASC
```

- Explicit Apex SOQL on a `__mdt` *does* count toward the SOQL governor (unlike
  `getAll()` / `getInstance()` lookups). The selector therefore caches results in
  a static `Map<String, List<…>>`, guaranteeing one query per transaction
  regardless of how many records the caller is processing.
- `applyRampPricing` is bulk-safe at 200 inputs — verified by the test
  `applyRampPricing_bulk200_governorSafe` (asserts ≤1 metadata query and ≤1
  `EventBus.publish` call for the entire batch).
- `EffectiveFromDate__c` filtering happens client-side after the query so that
  future-dated rows do not require date-bind parameters on a Custom Metadata SOQL.

## 7. Security model

| Surface                                       | Control                                                   |
|-----------------------------------------------|-----------------------------------------------------------|
| Apex                                          | `with sharing` everywhere.                                |
| SOQL on `BulkBillingRampSetting__mdt`         | Metadata; FLS-on-read does not apply, but `IsActive__c` and `EffectiveFromDate__c` give Finance a non-code kill switch. |
| `previewRamp` (`@AuraEnabled cacheable=true`) | Pure compute, no DML, no row-level data. Safe for cacheability. |
| `applyRampPricing` (`@InvocableMethod`)       | Idempotent on inputs; publish is opt-in via `publishEvent` boolean — admins can run dry-builds from Flow. |
| Permission set                                | `RCA_Sales_User` gets explicit class access, no extra object grants. |
| Platform event                                | `HighVolume` + `PublishAfterCommit` to guarantee Salesforce-side durability before Zuora subscribers see it. |

No user-supplied SOQL bind variables; no dynamic SOQL anywhere in the package.

## 8. Edge cases handled

- Year requested beyond the ramp (e.g. Year 99) → returns 0% (standard pricing).
- Unknown product code → `getActiveRampForProduct` returns an empty list, not an exception. The service-level validation throws only for **blank** product codes.
- Term = 0 / Term > 30 → `RCAException` with a clear message.
- Negative `baseAnnualPrice` → `RCAException`.
- Empty/`null` envelope list passed to publisher → no-op, returns empty result list.
- Future-dated `EffectiveFromDate__c` → row ignored at runtime.
- Inactive (`IsActive__c = false`) row → filtered at SOQL level.
- Rounding sanity: `1000 × 80% = 800.00` (not 799.99) verified by test.

## 9. Performance characteristics

| Operation                        | Cost                                      |
|----------------------------------|-------------------------------------------|
| First call in a Tx               | 1 SOQL on metadata (cached for the Tx).   |
| Subsequent calls in same Tx      | O(1) map lookup.                          |
| `buildEnvelope` (per row)        | O(termYears), capped at 30.               |
| `applyRampPricing` (N inputs)    | O(N × termYears), one publish batch.      |

## 10. Risks & assumptions

| Risk                                                                | Mitigation                                                       |
|---------------------------------------------------------------------|------------------------------------------------------------------|
| Finance changes ramp mid-contract                                   | `EffectiveFromDate__c` filter; existing contracts re-quoted only if a downstream amendment fires. |
| Multiple "active" rows for same (product, year)                     | Selector iterates in `ORDER BY ProductCode__c, YearNumber__c`; first wins. Recommend governance rule + report. |
| Subscriber failure on `BulkBilling_Orchestration__e`                | `PublishAfterCommit` + Salesforce platform retry; alerting in Zuora subscriber is out of scope here. |
| LWC `cacheable=true` may serve stale data after metadata edit       | Acceptable — discount values are rarely edited. Users can refresh the page; LDS auto-evicts within minutes. |

### Assumptions

- BB1 always sold in whole years (no monthly proration in scope for KAN-8).
- Currency rounding follows Zuora's HALF_UP convention; no FX in scope here.
- Order Orchestration and Zuora integration consume the event via standard
  Platform Event subscriber pattern (separate tickets).

## 11. Test plan

| Layer | Class / Spec                                  | Scope                                                 |
|-------|-----------------------------------------------|-------------------------------------------------------|
| Apex  | `RCABulkBillingServiceTest`                   | Discount lookup; envelope math; period boundaries; TCV; bulk-200; publish success; empty/null inputs; selector edge cases; all `RCAException` paths. |
| LWC   | `__tests__/rcaBulkBillingRampViewer.test.js` | Renders table from wire; surfaces wire errors.        |

Target coverage on `RCABulkBilling*` ≥ 90 %; org-wide remains > 85 %.

## 12. Monitoring & logging

- Subscribe a custom Apex trigger on `BulkBilling_Orchestration__e` in the Zuora
  integration package to log publish/replay/seek metrics.
- Add a Platform Event monitoring dashboard (Setup → Event Monitoring) tracking
  `BulkBilling_Orchestration__e` publish rate and any `EventBus.TriggerContext.currentContext().retries`.
- Recommend a Salesforce Health Check item: report on metadata rows where
  `IsActive__c=true AND DiscountPercentage__c > 50` (sanity bound).
