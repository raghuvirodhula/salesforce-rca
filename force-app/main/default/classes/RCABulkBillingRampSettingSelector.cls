/**
 * RCABulkBillingRampSettingSelector
 *
 * Selector for BulkBillingRampSetting__mdt. Centralises every read of the
 * ramp metadata behind a single, cached, test-injectable entry point.
 *
 * Why a selector:
 *   - One query per transaction (cached static map) — never re-queries
 *   - Tests can inject deterministic ramps via setMockSettings()
 *   - Filters (active rows, effective-date, product code) live in one place
 *
 * API 66.0  (Spring '26)
 */
public with sharing class RCABulkBillingRampSettingSelector {

    private static Map<String, List<BulkBillingRampSetting__mdt>> cacheByProduct;

    /**
     * Returns the active ramp rows for the given product code, sorted by year.
     * Effective-date filter applies (rows in the future are skipped).
     */
    public static List<BulkBillingRampSetting__mdt> getActiveRampForProduct(String productCode) {
        if (String.isBlank(productCode)) {
            throw new RCAException('Product code is required for ramp lookup.');
        }
        if (cacheByProduct == null) {
            loadAll();
        }
        List<BulkBillingRampSetting__mdt> rows = cacheByProduct.get(productCode.toUpperCase());
        return rows == null ? new List<BulkBillingRampSetting__mdt>() : rows;
    }

    /**
     * Returns the discount percentage for (productCode, yearNumber).
     * 0.00 if no active row exists for that year (= standard pricing).
     */
    public static Decimal getDiscountForYear(String productCode, Integer yearNumber) {
        for (BulkBillingRampSetting__mdt row : getActiveRampForProduct(productCode)) {
            if (row.YearNumber__c != null && row.YearNumber__c.intValue() == yearNumber) {
                return row.DiscountPercentage__c == null ? 0.00 : row.DiscountPercentage__c;
            }
        }
        return 0.00;
    }

    // ─── Internals ────────────────────────────────────────────────────────────

    private static void loadAll() {
        cacheByProduct = new Map<String, List<BulkBillingRampSetting__mdt>>();

        // Custom Metadata reads do not honour FLS — they are tooling-config records.
        // We still filter for IsActive__c and EffectiveFromDate__c at the runtime layer.
        Date today = Date.today();
        List<BulkBillingRampSetting__mdt> rows = [
            SELECT ProductCode__c, YearNumber__c, DiscountPercentage__c,
                   IsActive__c, EffectiveFromDate__c
            FROM BulkBillingRampSetting__mdt
            WHERE IsActive__c = true
            ORDER BY ProductCode__c ASC, YearNumber__c ASC
        ];

        for (BulkBillingRampSetting__mdt row : rows) {
            if (row.EffectiveFromDate__c != null && row.EffectiveFromDate__c > today) {
                continue;
            }
            String key = (row.ProductCode__c == null ? '' : row.ProductCode__c).toUpperCase();
            if (!cacheByProduct.containsKey(key)) {
                cacheByProduct.put(key, new List<BulkBillingRampSetting__mdt>());
            }
            cacheByProduct.get(key).add(row);
        }
    }

    /**
     * Test-only hook. Injects a deterministic ramp without touching metadata.
     */
    @TestVisible
    private static void setMockSettings(String productCode, List<BulkBillingRampSetting__mdt> rows) {
        if (cacheByProduct == null) cacheByProduct = new Map<String, List<BulkBillingRampSetting__mdt>>();
        cacheByProduct.put(productCode.toUpperCase(), rows);
    }

    /** Test-only: clear the cache between scenarios. */
    @TestVisible
    private static void clearCache() {
        cacheByProduct = null;
    }
}
