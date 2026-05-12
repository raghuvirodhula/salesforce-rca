/**
 * @description Service class for Bulk Billing logic, specifically handling ramp pricing calculations.
 * Aligned with KAN-3 requirements.
 * 
 * @author Antigravity (Salesforce TA)
 * @date 2024-05-12
 */
public with sharing class BulkBillingService {
    
    private static Map<Integer, Decimal> rampDiscounts;

    /**
     * @description Retrieves the discount percentage for a given year based on Custom Metadata.
     * @param yearNumber The year of the subscription (1, 2, 3, etc.)
     * @return Decimal The discount percentage (e.g., 20.00 for 20%)
     */
    public static Decimal getDiscountPercentage(Integer yearNumber) {
        if (rampDiscounts == null) {
            loadRampSettings();
        }
        
        // Return configured discount or 0.00 if no record found for the year
        return rampDiscounts.containsKey(yearNumber) ? rampDiscounts.get(yearNumber) : 0.00;
    }

    /**
     * @description Internal method to cache metadata settings into a map for performance.
     */
    private static void loadRampSettings() {
        rampDiscounts = new Map<Integer, Decimal>();
        
        // Query Custom Metadata
        List<BulkBillingRampSetting__mdt> settings = [
            SELECT YearNumber__c, DiscountPercentage__c 
            FROM BulkBillingRampSetting__mdt
        ];

        for (BulkBillingRampSetting__mdt setting : settings) {
            rampDiscounts.put(setting.YearNumber__c.intValue(), setting.DiscountPercentage__c);
        }
    }
}
