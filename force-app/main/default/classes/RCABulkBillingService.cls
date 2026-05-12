/**
 * RCABulkBillingService
 *
 * Production entry point for KAN-8: BB1 bulk billing product + ramp pricing.
 *
 * Responsibilities:
 *   1. Resolve the ramp discount for any (productCode, year) — single source of truth.
 *   2. Build a Zuora-ready RCABulkBillingPayload.Envelope from a base annual price.
 *   3. Publish a BulkBilling_Orchestration__e platform event so Order Orchestration
 *      and the Zuora integration can consume the ramp asynchronously.
 *
 * Surfaces:
 *   - Static Apex API (other services / batch / queueables)
 *   - @AuraEnabled methods for LWC (rcaBulkBillingRampViewer)
 *   - @InvocableMethod for Flow Builder (orchestration entry from screen flow)
 *
 * Design rules followed (CLAUDE.md + .claude/rules/salesforce-conventions.md):
 *   - with sharing
 *   - No SOQL/DML in loops — all bulk operations work on collections
 *   - WITH USER_MODE on SObject reads
 *   - Custom exception (RCAException) for all error paths
 *   - Cached metadata via RCABulkBillingRampSettingSelector
 *
 * API 66.0  (Spring '26)
 */
public with sharing class RCABulkBillingService {

    public static final String PRODUCT_CODE_BB1 = 'BB1';
    private static final Integer MAX_TERM_YEARS = 30;

    // ─── 1. Discount lookup ──────────────────────────────────────────────────

    /**
     * Returns the discount percentage applied for a given year of a given product.
     * 0 = post-ramp / standard pricing.
     */
    public static Decimal getDiscountPercentage(String productCode, Integer yearNumber) {
        validateProductCode(productCode);
        validateYearNumber(yearNumber);
        return RCABulkBillingRampSettingSelector.getDiscountForYear(productCode, yearNumber);
    }

    // ─── 2. Payload construction ─────────────────────────────────────────────

    /**
     * Build a ramp-priced envelope for a contract.
     *
     * @param productCode        Product (e.g. 'BB1')
     * @param contextRecordId    Originating record (Quote/Order/Asset/Property)
     * @param contractStartDate  Contract effective date
     * @param termYears          Contract length in years (1..MAX_TERM_YEARS)
     * @param baseAnnualPrice    List price before ramp discount
     * @return                   Populated Envelope, ready for JSON serialization
     */
    public static RCABulkBillingPayload.Envelope buildEnvelope(
        String  productCode,
        Id      contextRecordId,
        Date    contractStartDate,
        Integer termYears,
        Decimal baseAnnualPrice
    ) {
        validateProductCode(productCode);
        if (contextRecordId == null) {
            throw new RCAException('Context record Id is required.');
        }
        if (contractStartDate == null) {
            throw new RCAException('Contract start date is required.');
        }
        if (termYears == null || termYears < 1 || termYears > MAX_TERM_YEARS) {
            throw new RCAException('Term years must be between 1 and ' + MAX_TERM_YEARS + '.');
        }
        if (baseAnnualPrice == null || baseAnnualPrice < 0) {
            throw new RCAException('Base annual price must be a non-negative number.');
        }

        RCABulkBillingPayload.Envelope env = new RCABulkBillingPayload.Envelope();
        env.productCode         = productCode;
        env.contextRecordId     = contextRecordId;
        env.contractStartDate   = contractStartDate;
        env.termYears           = termYears;
        env.baseAnnualPrice     = baseAnnualPrice;
        env.totalContractValue  = 0;

        for (Integer y = 1; y <= termYears; y++) {
            Decimal disc = RCABulkBillingRampSettingSelector.getDiscountForYear(productCode, y);
            // Years past the configured ramp inherit the highest configured year (treat as standard).
            // For BB1: year 3+ rows have 0% by design.
            Decimal netPrice = (baseAnnualPrice * (100 - disc) / 100).setScale(2, System.RoundingMode.HALF_UP);

            Date periodStart = contractStartDate.addYears(y - 1);
            Date periodEnd   = contractStartDate.addYears(y).addDays(-1);

            env.tiers.add(new RCABulkBillingPayload.RampTier(y, disc, netPrice, periodStart, periodEnd));
            env.totalContractValue += netPrice;
        }
        env.totalContractValue = env.totalContractValue.setScale(2, System.RoundingMode.HALF_UP);
        return env;
    }

    // ─── 3. Platform event publish (orchestration handoff) ───────────────────

    /**
     * Publishes BulkBilling_Orchestration__e events for a batch of envelopes.
     * Caller batches; this method never publishes inside a loop.
     *
     * @return Database.SaveResult per event (in input order).
     */
    public static List<Database.SaveResult> publishOrchestrationEvents(
        List<RCABulkBillingPayload.Envelope> envelopes
    ) {
        if (envelopes == null || envelopes.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        List<BulkBilling_Orchestration__e> events = new List<BulkBilling_Orchestration__e>();
        for (RCABulkBillingPayload.Envelope env : envelopes) {
            events.add(new BulkBilling_Orchestration__e(
                ProductCode__c       = env.productCode,
                ContextRecordId__c   = String.valueOf(env.contextRecordId),
                ContractStartDate__c = env.contractStartDate,
                BaseAnnualPrice__c   = env.baseAnnualPrice,
                RampPayloadJson__c   = env.toJson()
            ));
        }
        return EventBus.publish(events);
    }

    // ─── 4. LWC entry point ──────────────────────────────────────────────────

    /**
     * Cacheable @AuraEnabled — used by rcaBulkBillingRampViewer to display
     * the ramp schedule and a price preview on a record page.
     */
    @AuraEnabled(cacheable=true)
    public static RCABulkBillingPayload.Envelope previewRamp(
        String  productCode,
        Date    contractStartDate,
        Integer termYears,
        Decimal baseAnnualPrice
    ) {
        // contextRecordId is required by buildEnvelope; pass a deterministic placeholder
        // for preview use (no DML happens here, so the value is never persisted).
        Id previewContext = UserInfo.getUserId();
        return buildEnvelope(productCode, previewContext, contractStartDate, termYears, baseAnnualPrice);
    }

    // ─── 5. Flow entry point ─────────────────────────────────────────────────

    public class FlowRequest {
        @InvocableVariable(required=true) public String  productCode;
        @InvocableVariable(required=true) public Id      contextRecordId;
        @InvocableVariable(required=true) public Date    contractStartDate;
        @InvocableVariable(required=true) public Integer termYears;
        @InvocableVariable(required=true) public Decimal baseAnnualPrice;
        @InvocableVariable                public Boolean publishEvent;
    }

    public class FlowResponse {
        @InvocableVariable public String  rampPayloadJson;
        @InvocableVariable public Decimal totalContractValue;
        @InvocableVariable public Boolean eventPublished;
    }

    /**
     * Flow-invocable bulk action: build envelopes for every request and,
     * if requested, publish a single batch of orchestration events.
     */
    @InvocableMethod(
        label='Compute BB1 Ramp Pricing'
        description='Builds a BB1 ramp-pricing payload and (optionally) publishes a BulkBilling_Orchestration__e event.'
        category='Revenue Cloud Advanced'
    )
    public static List<FlowResponse> applyRampPricing(List<FlowRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<FlowResponse>();
        }
        List<RCABulkBillingPayload.Envelope> envelopes = new List<RCABulkBillingPayload.Envelope>();
        List<Boolean> shouldPublish = new List<Boolean>();
        for (FlowRequest req : requests) {
            envelopes.add(buildEnvelope(
                req.productCode, req.contextRecordId, req.contractStartDate,
                req.termYears, req.baseAnnualPrice
            ));
            shouldPublish.add(req.publishEvent == true);
        }

        // Single bulk publish of only the envelopes flagged for publish.
        List<RCABulkBillingPayload.Envelope> toPublish = new List<RCABulkBillingPayload.Envelope>();
        for (Integer i = 0; i < envelopes.size(); i++) {
            if (shouldPublish[i]) toPublish.add(envelopes[i]);
        }
        Map<Integer, Boolean> publishResultByIndex = new Map<Integer, Boolean>();
        if (!toPublish.isEmpty()) {
            List<Database.SaveResult> srs = publishOrchestrationEvents(toPublish);
            Integer pubIdx = 0;
            for (Integer i = 0; i < envelopes.size(); i++) {
                if (shouldPublish[i]) {
                    publishResultByIndex.put(i, srs[pubIdx].isSuccess());
                    pubIdx++;
                }
            }
        }

        List<FlowResponse> out = new List<FlowResponse>();
        for (Integer i = 0; i < envelopes.size(); i++) {
            FlowResponse r = new FlowResponse();
            r.rampPayloadJson    = envelopes[i].toJson();
            r.totalContractValue = envelopes[i].totalContractValue;
            r.eventPublished     = publishResultByIndex.containsKey(i)
                                    ? publishResultByIndex.get(i)
                                    : false;
            out.add(r);
        }
        return out;
    }

    // ─── Guards ──────────────────────────────────────────────────────────────

    private static void validateProductCode(String productCode) {
        if (String.isBlank(productCode)) {
            throw new RCAException('Product code is required.');
        }
    }

    private static void validateYearNumber(Integer yearNumber) {
        if (yearNumber == null || yearNumber < 1) {
            throw new RCAException('Year number must be a positive integer.');
        }
    }
}
