/**
 * RCAOrderService
 *
 * Handles Order activation, amendment, and Asset lifecycle
 * for native Revenue Cloud Advanced.
 *
 * Native objects:
 *   Order / OrderItem         - the transactional record post-quote
 *   Asset                     - represents what the customer owns/subscribes to
 *   AssetAction               - amendments, renewals, cancellations on an Asset
 *   Contract / ContractLineItem - the legal agreement
 *   BillingSchedule           - auto-created by platform on Order activation
 *
 * @author  RCA Dev Team
 * @version 1.0  (API 66.0 - Spring '26)
 */
public with sharing class RCAOrderService {

    // ─── Order Lifecycle ──────────────────────────────────────────────────────

    /**
     * Activates a Draft Order.
     * On activation, the platform automatically creates BillingSchedule records
     * per OrderItem based on the ProductSellingModel configuration.
     *
     * @param orderId  Order to activate
     */
    public static void activateOrder(Id orderId) {
        Order ord = [
            SELECT Id, Status
            FROM Order
            WHERE Id = :orderId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (ord.Status != 'Draft') {
            throw new RCAException('Only Draft orders can be activated.');
        }

        ord.Status = 'Activated';
        update ord;
    }

    /**
     * Cancels an Activated Order and voids any pending BillingSchedules.
     *
     * @param orderId      Order to cancel
     * @param cancelReason Reason for cancellation
     */
    public static void cancelOrder(Id orderId, String cancelReason) {
        Order ord = [
            SELECT Id, Status
            FROM Order
            WHERE Id = :orderId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (ord.Status != 'Activated') {
            throw new RCAException('Only Activated orders can be cancelled.');
        }

        // Void pending billing schedules
        List<BillingSchedule> schedules = [
            SELECT Id, Status
            FROM BillingSchedule
            WHERE OrderItem.OrderId = :orderId
              AND Status = 'Active'
            WITH SECURITY_ENFORCED
        ];

        for (BillingSchedule s : schedules) {
            s.Status = 'Cancelled';
        }
        if (!schedules.isEmpty()) {
            update schedules;
        }

        ord.Status = 'Cancelled';
        update ord;
    }

    // ─── Asset Management ─────────────────────────────────────────────────────

    /**
     * Returns Assets owned by a given Account, optionally filtered by status.
     * Assets in native RCA represent active subscriptions or entitlements.
     *
     * @param accountId  Account to query
     * @param status     Asset status filter (null = all)
     * @return           List of Asset records
     */
    public static List<Asset> getAccountAssets(Id accountId, String status) {
        String baseQuery =
            'SELECT Id, Name, Product2Id, Product2.Name, Status, ' +
            '       Quantity, Price, PurchaseDate, UsageEndDate, ' +
            '       LifecycleStartDate, LifecycleEndDate ' +
            'FROM Asset ' +
            'WHERE AccountId = :accountId ' +
            'WITH SECURITY_ENFORCED ';

        if (String.isNotBlank(status)) {
            baseQuery += 'AND Status = :status ';
        }

        baseQuery += 'ORDER BY LifecycleEndDate ASC';

        return (List<Asset>) Database.query(baseQuery);
    }

    /**
     * Records an AssetAction for an amendment (upgrade, downgrade, add-on).
     * AssetAction is the native RCA mechanism for mid-term changes.
     *
     * @param assetId       Asset being amended
     * @param actionType    'Amend', 'Renew', or 'Cancel'
     * @param effectiveDate Date the action takes effect
     * @param newQuantity   New quantity (null = no change)
     * @return              Inserted AssetAction Id
     */
    public static Id recordAssetAction(
        Id      assetId,
        String  actionType,
        Date    effectiveDate,
        Decimal newQuantity
    ) {
        AssetAction action = new AssetAction(
            AssetId       = assetId,
            ActionType    = actionType,
            EffectiveDate = effectiveDate,
            Quantity      = newQuantity
        );

        insert action;
        return action.Id;
    }

    // ─── Contract Management ──────────────────────────────────────────────────

    /**
     * Creates a Contract from an Activated Order.
     * In native RCA, Contracts store committed terms and feed into
     * renewal automation.
     *
     * @param orderId  Activated Order to contract
     * @return         Inserted Contract Id
     */
    public static Id createContractFromOrder(Id orderId) {
        Order ord = [
            SELECT Id, AccountId, EffectiveDate, EndDate, CurrencyIsoCode
            FROM Order
            WHERE Id = :orderId
              AND Status = 'Activated'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Contract c = new Contract(
            AccountId          = ord.AccountId,
            StartDate          = ord.EffectiveDate,
            ContractTerm       = 12,         // months — adjust via custom metadata
            CurrencyIsoCode    = ord.CurrencyIsoCode,
            Status             = 'Draft'
        );

        insert c;
        return c.Id;
    }

    // ─── Batch Activation ─────────────────────────────────────────────────────

    /**
     * Kicks off the nightly batch to activate all pending Draft orders
     * whose EffectiveDate is today or earlier.
     *
     * @return  AsyncApexJob Id
     */
    public static Id schedulePendingOrderBatch() {
        return Database.executeBatch(new RCAOrderActivationBatch(), 50);
    }
}
