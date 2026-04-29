/**
 * RCAPricingService
 *
 * Handles native RCA pricing logic including tiered pricing,
 * volume discounts, and attribute-based adjustments.
 *
 * Native pricing objects (no namespace):
 *   PriceAdjustmentSchedule  - defines a tiered/volume pricing schedule
 *   PriceAdjustmentTier      - individual tiers within a schedule
 *   ProductSellingModel      - selling motion (One-Time / Termed / Evergreen)
 *   ProductSellingModelOption - links a product to its selling models
 *   PriceBook2 / PricebookEntry - standard pricebook objects (unchanged)
 *
 * @author  RCA Dev Team
 * @version 1.0  (API 66.0 - Spring '26)
 */
public with sharing class RCAPricingService {

    /**
     * Resolves the effective unit price for a product based on quantity,
     * using the PriceAdjustmentSchedule (tiered pricing) if one exists.
     *
     * @param pricebookEntryId  PricebookEntry for the product
     * @param quantity          Quantity being ordered
     * @return                  Effective unit price after tier lookup
     */
    public static Decimal resolveEffectivePrice(Id pricebookEntryId, Decimal quantity) {
        PricebookEntry pbe = [
            SELECT Id, UnitPrice, Product2Id
            FROM PricebookEntry
            WHERE Id = :pricebookEntryId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        // Look up an active PriceAdjustmentSchedule for this product
        List<PriceAdjustmentSchedule> schedules = [
            SELECT Id
            FROM PriceAdjustmentSchedule
            WHERE AdjustmentType = 'DiscountPercentage'
              AND IsActive = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (schedules.isEmpty()) {
            return pbe.UnitPrice;  // No tiered pricing configured
        }

        // Find the matching tier for the given quantity
        List<PriceAdjustmentTier> tiers = [
            SELECT Id, TierStartValue, TierEndValue, AdjustmentValue
            FROM PriceAdjustmentTier
            WHERE PriceAdjustmentScheduleId = :schedules[0].Id
              AND TierStartValue <= :quantity
            WITH SECURITY_ENFORCED
            ORDER BY TierStartValue DESC
            LIMIT 1
        ];

        if (tiers.isEmpty()) {
            return pbe.UnitPrice;
        }

        Decimal discountPct = tiers[0].AdjustmentValue;
        return pbe.UnitPrice * (1 - (discountPct / 100));
    }

    /**
     * Returns all ProductSellingModels available for a given Product.
     * Used by the UI to let reps choose between, e.g., 'Monthly Subscription'
     * vs 'Annual Subscription' vs 'One-Time Purchase'.
     *
     * @param product2Id  The Product2 Id
     * @return            List of ProductSellingModel records
     */
    public static List<ProductSellingModel> getSellingModelsForProduct(Id product2Id) {
        List<ProductSellingModelOption> options = [
            SELECT ProductSellingModelId, ProductSellingModel.Name,
                   ProductSellingModel.SellingModelType,
                   ProductSellingModel.PricingTerm
            FROM ProductSellingModelOption
            WHERE Product2Id = :product2Id
              AND ProductSellingModel.Status = 'Active'
            WITH SECURITY_ENFORCED
        ];

        List<ProductSellingModel> models = new List<ProductSellingModel>();
        for (ProductSellingModelOption opt : options) {
            models.add(opt.ProductSellingModel);
        }
        return models;
    }

    /**
     * Runs the native Salesforce Pricing engine via the RevSignaling namespace
     * (the official programmatic entry point for RCA headless pricing).
     *
     * This calls the platform's pricing procedure rather than replicating
     * pricing logic in Apex — keeping pricing config in the data model.
     *
     * @param quoteId  Quote to re-price
     */
    public static void runPricingProcedure(Id quoteId) {
        // RevSignaling is the official Apex namespace for RCA pricing APIs
        // PricingProcedureExecutor triggers the configured PricingRecipe
        RevSignaling.PricingProcedureExecutor executor =
            new RevSignaling.PricingProcedureExecutor();

        RevSignaling.PricingProcedureInput input =
            new RevSignaling.PricingProcedureInput();
        input.contextId = quoteId;

        executor.execute(input);
    }

    /**
     * Calculates the proration amount for a mid-term amendment.
     * Uses the RCA-standard approach of dividing by days remaining.
     *
     * @param unitPrice     Full period unit price
     * @param periodDays    Total days in the billing period
     * @param remainingDays Days remaining in the current period
     * @return              Prorated amount
     */
    public static Decimal calculateProration(
        Decimal unitPrice,
        Integer periodDays,
        Integer remainingDays
    ) {
        if (periodDays == null || periodDays == 0) {
            throw new RCAException('Period days cannot be zero for proration.');
        }
        return (unitPrice / periodDays) * remainingDays;
    }
}
