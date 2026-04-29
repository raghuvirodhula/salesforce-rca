/**
 * RCABillingService
 *
 * Service class for native Revenue Cloud Advanced billing operations.
 *
 * Native objects used (no blng__ namespace):
 *   BillingSchedule       - stores invoicing cadence per OrderItem
 *   BillingScheduleGroup  - groups related billing schedules
 *   Invoice               - the invoice header
 *   InvoiceLine           - individual line on an invoice
 *   CreditMemo            - adjustments and credits
 *
 * @author  RCA Dev Team
 * @version 1.0  (API 66.0 - Spring '26)
 */
public with sharing class RCABillingService {

    // ─── Invoice Generation ───────────────────────────────────────────────────

    /**
     * Finds all BillingSchedules due on or before today and generates Invoices.
     * BillingSchedule is a native standard object in RCA (no namespace).
     *
     * @return  Count of invoices created
     */
    public static Integer generateDueInvoices() {
        Date today = Date.today();

        List<BillingSchedule> dueSchedules = [
            SELECT Id, BillingAccountId, NextBillingDate,
                   BillingFrequency, OrderItemId, TotalAmount
            FROM BillingSchedule
            WHERE NextBillingDate <= :today
              AND Status = 'Active'
            WITH SECURITY_ENFORCED
        ];

        if (dueSchedules.isEmpty()) {
            return 0;
        }

        List<Invoice> invoicesToInsert = new List<Invoice>();
        for (BillingSchedule sched : dueSchedules) {
            invoicesToInsert.add(new Invoice(
                BillingAccountId   = sched.BillingAccountId,
                BillingScheduleId  = sched.Id,
                InvoiceDate        = today,
                DueDate            = today.addDays(30),
                Status             = 'Draft',
                TotalAmount        = sched.TotalAmount
            ));
        }

        insert invoicesToInsert;
        return invoicesToInsert.size();
    }

    /**
     * Posts (finalises) Draft invoices, making them eligible for payment.
     *
     * @param invoiceIds  Set of Invoice Ids to post
     */
    public static void postInvoices(Set<Id> invoiceIds) {
        List<Invoice> invoices = [
            SELECT Id, Status
            FROM Invoice
            WHERE Id IN :invoiceIds
              AND Status = 'Draft'
            WITH SECURITY_ENFORCED
        ];

        for (Invoice inv : invoices) {
            inv.Status = 'Posted';
        }

        if (!invoices.isEmpty()) {
            update invoices;
        }
    }

    /**
     * Creates a CreditMemo against a Posted invoice.
     * Used for full or partial credits.
     *
     * @param invoiceId    Invoice to credit
     * @param creditAmount Amount to credit
     * @param reason       Reason description
     * @return             Inserted CreditMemo Id
     */
    public static Id createCreditMemo(Id invoiceId, Decimal creditAmount, String reason) {
        Invoice inv = [
            SELECT Id, BillingAccountId, Status, TotalAmount
            FROM Invoice
            WHERE Id = :invoiceId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (inv.Status != 'Posted') {
            throw new RCAException('Credit memos can only be raised against Posted invoices.');
        }

        CreditMemo cm = new CreditMemo(
            BillingAccountId = inv.BillingAccountId,
            InvoiceId        = invoiceId,
            CreditMemoDate   = Date.today(),
            TotalAmount      = creditAmount,
            Description      = reason,
            Status           = 'Draft'
        );

        insert cm;
        return cm.Id;
    }

    // ─── Billing Schedule Management ──────────────────────────────────────────

    /**
     * Advances the NextBillingDate on a BillingSchedule
     * based on its BillingFrequency (Monthly, Quarterly, Annually, Weekly).
     *
     * @param scheduleId  BillingSchedule to advance
     */
    public static void advanceBillingSchedule(Id scheduleId) {
        BillingSchedule sched = [
            SELECT Id, NextBillingDate, BillingFrequency
            FROM BillingSchedule
            WHERE Id = :scheduleId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        sched.NextBillingDate = nextDateFromFrequency(
            sched.NextBillingDate,
            sched.BillingFrequency
        );

        update sched;
    }

    /**
     * Returns billing schedules associated with a given Order.
     *
     * @param orderId  Order Id
     * @return         List of BillingSchedule records
     */
    public static List<BillingSchedule> getSchedulesForOrder(Id orderId) {
        return [
            SELECT Id, BillingAccountId, NextBillingDate, BillingFrequency,
                   Status, TotalAmount, OrderItemId
            FROM BillingSchedule
            WHERE OrderItem.OrderId = :orderId
            WITH SECURITY_ENFORCED
            ORDER BY NextBillingDate ASC
        ];
    }

    // ─── Usage-Based Billing ──────────────────────────────────────────────────

    /**
     * Aggregates UsageSummary records for a BillingSchedule
     * and sets the TotalAmount ready for invoicing.
     * UsageSummary is a native RCA object for consumption-based pricing.
     *
     * @param scheduleId  BillingSchedule to rate
     * @return            Calculated usage total
     */
    public static Decimal rateUsageForSchedule(Id scheduleId) {
        AggregateResult result = [
            SELECT SUM(BilledAmount) total
            FROM UsageSummary
            WHERE BillingScheduleId = :scheduleId
              AND Status = 'Pending'
            WITH SECURITY_ENFORCED
        ];

        Decimal total = (Decimal) result.get('total') ?? 0;

        update new BillingSchedule(
            Id          = scheduleId,
            TotalAmount = total
        );

        return total;
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private static Date nextDateFromFrequency(Date current, String frequency) {
        switch on frequency {
            when 'Monthly'   { return current.addMonths(1); }
            when 'Quarterly' { return current.addMonths(3); }
            when 'Annually'  { return current.addYears(1); }
            when 'Weekly'    { return current.addDays(7); }
            when else        { return current.addMonths(1); }
        }
    }
}
