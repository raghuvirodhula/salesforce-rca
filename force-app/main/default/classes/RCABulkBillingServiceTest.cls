/**
 * RCABulkBillingServiceTest
 *
 * Coverage targets:
 *   - Discount lookup (year present / missing / standard / invalid input)
 *   - Envelope construction (math, period boundaries, TCV, ScaleRounding)
 *   - Platform-event publish (success + empty batch short-circuit)
 *   - Flow invocable (publish flag honoured, bulk safety @ 200 records)
 *   - LWC @AuraEnabled previewRamp
 *   - Exception paths (blank product, bad year, bad term, negative price, null ids/dates)
 *   - Selector cache: blank product throws, year > ramp returns 0
 *
 * Notes:
 *   - We inject mock ramp settings via RCABulkBillingRampSettingSelector.setMockSettings
 *     so the test does not depend on org-deployed CustomMetadata.
 *   - All assertions include a diagnostic message.
 */
@IsTest
private class RCABulkBillingServiceTest {

    private static final String P = RCABulkBillingService.PRODUCT_CODE_BB1;

    /** Build a fully-populated, in-memory ramp matching the BRD: 20% / 10% / 0%. */
    private static List<BulkBillingRampSetting__mdt> buildBB1Ramp() {
        List<BulkBillingRampSetting__mdt> rows = new List<BulkBillingRampSetting__mdt>();
        rows.add(new BulkBillingRampSetting__mdt(
            ProductCode__c=P, YearNumber__c=1, DiscountPercentage__c=20.0,
            IsActive__c=true,  EffectiveFromDate__c=Date.newInstance(2026,1,1)
        ));
        rows.add(new BulkBillingRampSetting__mdt(
            ProductCode__c=P, YearNumber__c=2, DiscountPercentage__c=10.0,
            IsActive__c=true,  EffectiveFromDate__c=Date.newInstance(2026,1,1)
        ));
        rows.add(new BulkBillingRampSetting__mdt(
            ProductCode__c=P, YearNumber__c=3, DiscountPercentage__c=0.0,
            IsActive__c=true,  EffectiveFromDate__c=Date.newInstance(2026,1,1)
        ));
        return rows;
    }

    @TestSetup
    static void primeCache() {
        RCABulkBillingRampSettingSelector.clearCache();
        RCABulkBillingRampSettingSelector.setMockSettings(P, buildBB1Ramp());
    }

    // ─── Discount lookup ─────────────────────────────────────────────────────

    @IsTest
    static void getDiscount_returnsConfiguredYearValues() {
        RCABulkBillingRampSettingSelector.setMockSettings(P, buildBB1Ramp());

        System.assertEquals(20.0, RCABulkBillingService.getDiscountPercentage(P, 1),
            'Year 1 must be 20% discount');
        System.assertEquals(10.0, RCABulkBillingService.getDiscountPercentage(P, 2),
            'Year 2 must be 10% discount');
        System.assertEquals(0.0,  RCABulkBillingService.getDiscountPercentage(P, 3),
            'Year 3 must be 0% (standard pricing)');
        System.assertEquals(0.0,  RCABulkBillingService.getDiscountPercentage(P, 99),
            'Years beyond the ramp must fall back to 0% (standard)');
    }

    @IsTest
    static void getDiscount_blankProduct_throws() {
        try {
            RCABulkBillingService.getDiscountPercentage('   ', 1);
            System.assert(false, 'Blank product code should have thrown RCAException');
        } catch (RCAException e) {
            System.assert(e.getMessage().containsIgnoreCase('product code'),
                'Exception message must reference product code');
        }
    }

    @IsTest
    static void getDiscount_invalidYear_throws() {
        try {
            RCABulkBillingService.getDiscountPercentage(P, 0);
            System.assert(false, 'Year 0 should have thrown RCAException');
        } catch (RCAException e) {
            System.assert(e.getMessage().containsIgnoreCase('year'),
                'Exception must mention year');
        }
    }

    // ─── Envelope construction ───────────────────────────────────────────────

    @IsTest
    static void buildEnvelope_appliesRampMathAndPeriods() {
        RCABulkBillingRampSettingSelector.setMockSettings(P, buildBB1Ramp());

        Date start = Date.newInstance(2026, 7, 1);
        Test.startTest();
        RCABulkBillingPayload.Envelope env = RCABulkBillingService.buildEnvelope(
            P, UserInfo.getUserId(), start, 3, 1000
        );
        Test.stopTest();

        System.assertEquals(3, env.tiers.size(), 'Should produce one tier per contract year');
        System.assertEquals(800.00,  env.tiers[0].netAnnualPrice, 'Year 1 net = 1000 * 80%');
        System.assertEquals(900.00,  env.tiers[1].netAnnualPrice, 'Year 2 net = 1000 * 90%');
        System.assertEquals(1000.00, env.tiers[2].netAnnualPrice, 'Year 3 net = 1000 * 100%');
        System.assertEquals(2700.00, env.totalContractValue,
            'TCV must equal sum of net annual prices');

        // Period boundaries: each tier covers one year, end = next year start - 1 day.
        System.assertEquals(start,                                env.tiers[0].periodStartDate);
        System.assertEquals(start.addYears(1).addDays(-1),        env.tiers[0].periodEndDate);
        System.assertEquals(start.addYears(2),                    env.tiers[2].periodStartDate);
        System.assertEquals(start.addYears(3).addDays(-1),        env.tiers[2].periodEndDate);
    }

    @IsTest
    static void buildEnvelope_validatesAllInputs() {
        Date d = Date.newInstance(2026, 1, 1);
        Id uid = UserInfo.getUserId();

        Boolean t1=false, t2=false, t3=false, t4=false, t5=false;

        try { RCABulkBillingService.buildEnvelope(P, null, d, 1, 100); }
        catch (RCAException e) { t1 = true; }
        try { RCABulkBillingService.buildEnvelope(P, uid, null, 1, 100); }
        catch (RCAException e) { t2 = true; }
        try { RCABulkBillingService.buildEnvelope(P, uid, d, 0, 100); }
        catch (RCAException e) { t3 = true; }
        try { RCABulkBillingService.buildEnvelope(P, uid, d, 31, 100); }
        catch (RCAException e) { t4 = true; }
        try { RCABulkBillingService.buildEnvelope(P, uid, d, 1, -1); }
        catch (RCAException e) { t5 = true; }

        System.assert(t1, 'null contextRecordId must throw');
        System.assert(t2, 'null contractStartDate must throw');
        System.assert(t3, 'termYears=0 must throw');
        System.assert(t4, 'termYears>30 must throw');
        System.assert(t5, 'negative baseAnnualPrice must throw');
    }

    // ─── Platform-event publish ──────────────────────────────────────────────

    @IsTest
    static void publishOrchestrationEvents_emptyList_isNoOp() {
        Test.startTest();
        List<Database.SaveResult> srs1 = RCABulkBillingService.publishOrchestrationEvents(null);
        List<Database.SaveResult> srs2 = RCABulkBillingService.publishOrchestrationEvents(
            new List<RCABulkBillingPayload.Envelope>()
        );
        Test.stopTest();
        System.assertEquals(0, srs1.size(), 'null input returns empty list');
        System.assertEquals(0, srs2.size(), 'empty input returns empty list');
    }

    @IsTest
    static void publishOrchestrationEvents_singlePublishSucceeds() {
        RCABulkBillingRampSettingSelector.setMockSettings(P, buildBB1Ramp());
        RCABulkBillingPayload.Envelope env = RCABulkBillingService.buildEnvelope(
            P, UserInfo.getUserId(), Date.today(), 2, 500
        );
        Test.startTest();
        List<Database.SaveResult> srs = RCABulkBillingService.publishOrchestrationEvents(
            new List<RCABulkBillingPayload.Envelope>{ env }
        );
        Test.stopTest();
        System.assertEquals(1, srs.size(), 'One SaveResult expected');
        System.assert(srs[0].isSuccess(), 'Platform event publish must succeed');
    }

    // ─── Flow invocable ──────────────────────────────────────────────────────

    @IsTest
    static void applyRampPricing_bulk200_governorSafe() {
        RCABulkBillingRampSettingSelector.setMockSettings(P, buildBB1Ramp());
        List<RCABulkBillingService.FlowRequest> reqs = new List<RCABulkBillingService.FlowRequest>();
        for (Integer i = 0; i < 200; i++) {
            RCABulkBillingService.FlowRequest r = new RCABulkBillingService.FlowRequest();
            r.productCode       = P;
            r.contextRecordId   = UserInfo.getUserId();
            r.contractStartDate = Date.newInstance(2026, 1, 1);
            r.termYears         = 3;
            r.baseAnnualPrice   = 1200;
            r.publishEvent      = (Math.mod(i, 2) == 0);  // half publish, half don't
            reqs.add(r);
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer publishesBefore = Limits.getPublishImmediateDML();
        List<RCABulkBillingService.FlowResponse> resps =
            RCABulkBillingService.applyRampPricing(reqs);
        Test.stopTest();

        System.assertEquals(200, resps.size(), 'One response per request');
        Integer publishedCount = 0;
        for (RCABulkBillingService.FlowResponse r : resps) {
            System.assertNotEquals(null, r.rampPayloadJson, 'Every response must carry payload JSON');
            System.assertEquals(3120.00, r.totalContractValue,
                'TCV at 1200 base: 960 + 1080 + 1200');
            if (r.eventPublished) publishedCount++;
        }
        System.assertEquals(100, publishedCount, 'Exactly 100 events should have been published');

        // Bulkification: we want at most one query for metadata + one publish call.
        System.assert(Limits.getQueries() - queriesBefore <= 1,
            'Should not query metadata per record (used '
            + (Limits.getQueries() - queriesBefore) + ' queries)');
        System.assert(Limits.getPublishImmediateDML() - publishesBefore <= 1,
            'Should issue at most one EventBus.publish call for the whole batch');
    }

    @IsTest
    static void applyRampPricing_emptyList_returnsEmpty() {
        List<RCABulkBillingService.FlowResponse> resps =
            RCABulkBillingService.applyRampPricing(new List<RCABulkBillingService.FlowRequest>());
        System.assertEquals(0, resps.size(), 'Empty input must return empty list');
        System.assertEquals(0,
            RCABulkBillingService.applyRampPricing(null).size(),
            'Null input must return empty list');
    }

    // ─── LWC preview ─────────────────────────────────────────────────────────

    @IsTest
    static void previewRamp_returnsEnvelopeWithoutPersisting() {
        RCABulkBillingRampSettingSelector.setMockSettings(P, buildBB1Ramp());
        Test.startTest();
        RCABulkBillingPayload.Envelope env = RCABulkBillingService.previewRamp(
            P, Date.newInstance(2026, 1, 1), 2, 200
        );
        Test.stopTest();
        System.assertEquals(2, env.tiers.size());
        System.assertEquals(160.00, env.tiers[0].netAnnualPrice, 'Y1: 200 * 80%');
        System.assertEquals(180.00, env.tiers[1].netAnnualPrice, 'Y2: 200 * 90%');
    }

    // ─── Selector edge cases ─────────────────────────────────────────────────

    @IsTest
    static void selector_blankProductThrows() {
        try {
            RCABulkBillingRampSettingSelector.getActiveRampForProduct('');
            System.assert(false, 'Blank product must throw');
        } catch (RCAException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void selector_unknownProductReturnsEmpty() {
        RCABulkBillingRampSettingSelector.setMockSettings(P, buildBB1Ramp());
        List<BulkBillingRampSetting__mdt> rows =
            RCABulkBillingRampSettingSelector.getActiveRampForProduct('UNKNOWN');
        System.assertEquals(0, rows.size(),
            'Unknown product must return empty list, not throw');
    }

}
