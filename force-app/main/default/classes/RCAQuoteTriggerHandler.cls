/**
 * RCAQuoteTriggerHandler
 * Business logic for the native Quote trigger.
 */
public with sharing class RCAQuoteTriggerHandler {

    public void onBeforeInsert(List<Quote> newQuotes) {
        setDefaultExpiration(newQuotes);
    }

    public void onBeforeUpdate(List<Quote> newQuotes, Map<Id, Quote> oldMap) {
        preventEditOnApproved(newQuotes, oldMap);
    }

    public void onAfterInsert(List<Quote> newQuotes) {
        // e.g. create related records, send notifications
    }

    public void onAfterUpdate(List<Quote> newQuotes, Map<Id, Quote> oldMap) {
        // Evaluate discounts when Status changes
        Set<Id> statusChanged = new Set<Id>();
        for (Quote q : newQuotes) {
            if (q.Status != oldMap.get(q.Id).Status) {
                statusChanged.add(q.Id);
            }
        }
        if (!statusChanged.isEmpty()) {
            RCAQuoteService.evaluateDiscountApproval(statusChanged);
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private void setDefaultExpiration(List<Quote> quotes) {
        for (Quote q : quotes) {
            if (q.ExpirationDate == null) {
                q.ExpirationDate = Date.today().addDays(30);
            }
        }
    }

    private void preventEditOnApproved(List<Quote> newQuotes, Map<Id, Quote> oldMap) {
        for (Quote q : newQuotes) {
            if (oldMap.get(q.Id).Status == 'Approved' && q.Status == 'Approved') {
                // Prevent changes to TotalPrice on approved quotes
                if (q.TotalPrice != oldMap.get(q.Id).TotalPrice) {
                    q.addError('Approved quotes cannot be repriced. Clone the quote to make changes.');
                }
            }
        }
    }
}
