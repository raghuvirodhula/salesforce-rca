/**
 * RCAQuoteServiceTest
 * Unit tests for RCAQuoteService using native RCA objects.
 */
@IsTest
private class RCAQuoteServiceTest {

    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Test RCA Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name         = 'Test RCA Opportunity',
            AccountId    = acc.Id,
            StageName    = 'Prospecting',
            CloseDate    = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert opp;
    }

    // ─── Quote Creation ───────────────────────────────────────────────────────

    @IsTest
    static void testCreateQuoteFromOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Quote q = RCAQuoteService.createQuoteFromOpportunity(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, q.Id, 'Quote Id should not be null');
        System.assertEquals('Draft', q.Status, 'New quote should be Draft');
        System.assertEquals(opp.Id, q.OpportunityId, 'Quote should link to Opportunity');
    }

    // ─── Quote Total ──────────────────────────────────────────────────────────

    @IsTest
    static void testGetQuoteTotal() {
        Opportunity opp = [SELECT Id, Pricebook2Id FROM Opportunity LIMIT 1];
        Quote q = RCAQuoteService.createQuoteFromOpportunity(opp.Id);

        // Set up product and pricebook entry
        Product2 prod = new Product2(Name = 'Platform Licence', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = prod.Id,
            UnitPrice    = 500.00,
            IsActive     = true
        );
        insert pbe;

        // Insert a QuoteLineItem directly (bypassing selling model for test simplicity)
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId          = q.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 2,
            UnitPrice        = 500.00,
            TotalPrice       = 1000.00
        );
        insert qli;

        Test.startTest();
        Decimal total = RCAQuoteService.getQuoteTotal(q.Id);
        Test.stopTest();

        System.assertEquals(1000.00, total, 'Quote total should be 1000.00');
    }

    // ─── Discount Approval ────────────────────────────────────────────────────

    @IsTest
    static void testEvaluateDiscountApproval_BelowThreshold() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Quote q = RCAQuoteService.createQuoteFromOpportunity(opp.Id);

        Product2 prod = new Product2(Name = 'Storage Add-On', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = prod.Id,
            UnitPrice    = 100.00,
            IsActive     = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId          = q.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 100.00,
            TotalPrice       = 90.00,
            Discount         = 10.0   // Below 20% threshold
        );
        insert qli;

        Test.startTest();
        RCAQuoteService.evaluateDiscountApproval(new Set<Id>{ q.Id });
        Test.stopTest();

        Quote result = [SELECT Status FROM Quote WHERE Id = :q.Id];
        System.assertEquals('Approved', result.Status, 'Should be auto-approved below threshold');
    }

    @IsTest
    static void testEvaluateDiscountApproval_AboveThreshold() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Quote q = RCAQuoteService.createQuoteFromOpportunity(opp.Id);

        Product2 prod = new Product2(Name = 'Enterprise Licence', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = prod.Id,
            UnitPrice    = 2000.00,
            IsActive     = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId          = q.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 2000.00,
            TotalPrice       = 1400.00,
            Discount         = 30.0   // Above 20% threshold
        );
        insert qli;

        Test.startTest();
        RCAQuoteService.evaluateDiscountApproval(new Set<Id>{ q.Id });
        Test.stopTest();

        Quote result = [SELECT Status FROM Quote WHERE Id = :q.Id];
        System.assertEquals('Needs Review', result.Status, 'High discount should need review');
    }

    // ─── Convert to Order ─────────────────────────────────────────────────────

    @IsTest
    static void testConvertQuoteToOrder_ThrowsIfNotApproved() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Quote q = RCAQuoteService.createQuoteFromOpportunity(opp.Id);
        // Remains Draft

        Test.startTest();
        try {
            RCAQuoteService.convertQuoteToOrder(q.Id);
            System.assert(false, 'Should have thrown RCAException');
        } catch (RCAException e) {
            System.assert(e.getMessage().contains('Approved'), 'Error should mention Approved');
        }
        Test.stopTest();
    }
}
