/**
 * RCAQuoteService
 *
 * Service class for native Revenue Cloud Advanced quoting.
 * Works with standard Salesforce Quote, QuoteLineItem, and
 * ProductSellingModel objects — no managed package namespace.
 *
 * Key native RCA objects used:
 *   Quote               - the quote header
 *   QuoteLineItem       - individual product lines
 *   ProductSellingModel - defines how a product is sold (one-time, evergreen, termed)
 *   PriceAdjustmentSchedule / PriceAdjustmentTier - tiered & volume pricing
 *
 * @author  RCA Dev Team
 * @version 1.0  (API 66.0 - Spring '26)
 */
public with sharing class RCAQuoteService {

    // ─── Constants ────────────────────────────────────────────────────────────
    private static final String STATUS_DRAFT        = 'Draft';
    private static final String STATUS_APPROVED     = 'Approved';
    private static final String STATUS_NEEDS_REVIEW = 'Needs Review';
    private static final Decimal APPROVAL_THRESHOLD = 20.0;  // discount % requiring approval

    // ─── Quote Creation ───────────────────────────────────────────────────────

    /**
     * Creates a native RCA Quote from an Opportunity.
     * The Quote is linked via the standard OpportunityId lookup.
     *
     * @param opportunityId  Source Opportunity
     * @return               Newly inserted Quote
     */
    public static Quote createQuoteFromOpportunity(Id opportunityId) {
        Opportunity opp = [
            SELECT Id, Name, AccountId, Pricebook2Id, CloseDate, CurrencyIsoCode
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Quote q = new Quote(
            OpportunityId    = opp.Id,
            Name             = 'Quote - ' + opp.Name,
            Pricebook2Id     = opp.Pricebook2Id,
            ExpirationDate   = opp.CloseDate,
            Status           = STATUS_DRAFT,
            CurrencyIsoCode  = opp.CurrencyIsoCode
        );

        insert q;
        return q;
    }

    /**
     * Adds a product line to a Quote, resolving the ProductSellingModel.
     * In native RCA, ProductSellingModel defines the selling motion
     * (e.g., 'Termed Subscription', 'Evergreen Subscription', 'One-Time Purchase').
     *
     * @param quoteId               The Quote to add the line to
     * @param pricebookEntryId      PricebookEntry for the product
     * @param quantity              Quantity
     * @param discount              Discount percentage (0–100)
     * @param sellingModelId        ProductSellingModel Id
     * @return                      Inserted QuoteLineItem
     */
    public static QuoteLineItem addLineToQuote(
        Id      quoteId,
        Id      pricebookEntryId,
        Decimal quantity,
        Decimal discount,
        Id      sellingModelId
    ) {
        PricebookEntry pbe = [
            SELECT Id, UnitPrice, Product2Id
            FROM PricebookEntry
            WHERE Id = :pricebookEntryId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Decimal unitPrice  = pbe.UnitPrice;
        Decimal lineTotal  = unitPrice * quantity * (1 - (discount / 100));

        QuoteLineItem line = new QuoteLineItem(
            QuoteId               = quoteId,
            PricebookEntryId      = pricebookEntryId,
            Quantity              = quantity,
            UnitPrice             = unitPrice,
            Discount              = discount,
            TotalPrice            = lineTotal,
            ProductSellingModelId = sellingModelId   // native RCA field
        );

        insert line;
        return line;
    }

    // ─── Discount Approval ────────────────────────────────────────────────────

    /**
     * Evaluates all lines on a set of Quotes and routes to approval
     * if any line exceeds the discount threshold.
     *
     * @param quoteIds  Quotes to evaluate
     */
    public static void evaluateDiscountApproval(Set<Id> quoteIds) {
        // Aggregate max discount per quote
        Map<Id, Decimal> maxDiscountByQuote = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT QuoteId, MAX(Discount) maxDisc
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
              AND Discount != null
            WITH SECURITY_ENFORCED
            GROUP BY QuoteId
        ]) {
            maxDiscountByQuote.put(
                (Id) ar.get('QuoteId'),
                (Decimal) ar.get('maxDisc')
            );
        }

        List<Quote> toUpdate = new List<Quote>();
        for (Id qId : quoteIds) {
            Decimal maxDisc = maxDiscountByQuote.get(qId) ?? 0;
            toUpdate.add(new Quote(
                Id     = qId,
                Status = maxDisc > APPROVAL_THRESHOLD ? STATUS_NEEDS_REVIEW : STATUS_APPROVED
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // ─── Quote Totals ─────────────────────────────────────────────────────────

    /**
     * Returns the net total across all QuoteLineItems for a given Quote.
     *
     * @param quoteId  Quote Id
     * @return         Net total as Decimal
     */
    public static Decimal getQuoteTotal(Id quoteId) {
        AggregateResult result = [
            SELECT SUM(TotalPrice) netTotal
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH SECURITY_ENFORCED
        ];
        return (Decimal) result.get('netTotal') ?? 0;
    }

    // ─── Convert to Order ─────────────────────────────────────────────────────

    /**
     * Converts an Approved Quote to a Draft Order.
     * In native RCA, Order and OrderItem are the standard objects —
     * the OrderItem carries ProductSellingModelId for subscription context.
     *
     * @param quoteId  Approved Quote to convert
     * @return         Inserted Order Id
     */
    public static Id convertQuoteToOrder(Id quoteId) {
        Quote q = [
            SELECT Id, OpportunityId, Pricebook2Id, AccountId, CurrencyIsoCode,
                   Status, ExpirationDate
            FROM Quote
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (q.Status != STATUS_APPROVED) {
            throw new RCAException('Only Approved quotes can be converted to Orders.');
        }

        Order ord = new Order(
            AccountId      = q.AccountId,
            OpportunityId  = q.OpportunityId,
            Pricebook2Id   = q.Pricebook2Id,
            CurrencyIsoCode = q.CurrencyIsoCode,
            EffectiveDate  = Date.today(),
            Status         = 'Draft'
        );
        insert ord;

        List<QuoteLineItem> lines = [
            SELECT PricebookEntryId, Quantity, UnitPrice, Discount,
                   TotalPrice, ProductSellingModelId, Product2Id
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH SECURITY_ENFORCED
        ];

        List<OrderItem> orderItems = new List<OrderItem>();
        for (QuoteLineItem qli : lines) {
            orderItems.add(new OrderItem(
                OrderId               = ord.Id,
                PricebookEntryId      = qli.PricebookEntryId,
                Quantity              = qli.Quantity,
                UnitPrice             = qli.UnitPrice,
                TotalPrice            = qli.TotalPrice,
                ProductSellingModelId = qli.ProductSellingModelId  // native RCA field
            ));
        }

        if (!orderItems.isEmpty()) {
            insert orderItems;
        }

        return ord.Id;
    }
}
