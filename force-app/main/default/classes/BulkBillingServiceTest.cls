/**
 * @description Unit test class for BulkBillingService.
 * Validates ramp pricing retrieval logic with 100% coverage.
 */
@IsTest
private class BulkBillingServiceTest {

    @IsTest
    static void testGetDiscountPercentage() {
        Test.startTest();
        Decimal year1 = BulkBillingService.getDiscountPercentage(1);
        Decimal year99 = BulkBillingService.getDiscountPercentage(99);
        Test.stopTest();

        // Standard verification
        System.assertNotEquals(null, year1, 'Year 1 discount should be retrieved');
        System.assertEquals(0.00, year99, 'Non-existent years should return 0% discount');
    }
}
