/**
 * RCAOrderActivationBatch
 *
 * Nightly batch that activates Draft Orders whose EffectiveDate
 * is today or earlier. Activation triggers the platform to
 * auto-create BillingSchedule records per OrderItem.
 */
public with sharing class RCAOrderActivationBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private Integer activated = 0;
    private Integer failed    = 0;
    private List<String> errors = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Status, AccountId, EffectiveDate
            FROM Order
            WHERE Status = 'Draft'
              AND EffectiveDate <= TODAY
            WITH SECURITY_ENFORCED
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Order> orders) {
        List<Order> toActivate = new List<Order>();
        for (Order o : orders) {
            toActivate.add(new Order(Id = o.Id, Status = 'Activated'));
        }

        Database.SaveResult[] results = Database.update(toActivate, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                activated++;
            } else {
                failed++;
                errors.add('Order ' + orders[i].Id + ': ' +
                    results[i].getErrors()[0].getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ 'sfadmin@yourcompany.com' });
        mail.setSubject('[RCA] Nightly Order Activation Complete');
        mail.setPlainTextBody(
            'Activated: ' + activated + '\n' +
            'Failed:    ' + failed    + '\n' +
            (errors.isEmpty() ? '' : '\nErrors:\n' + String.join(errors, '\n'))
        );
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }
}
