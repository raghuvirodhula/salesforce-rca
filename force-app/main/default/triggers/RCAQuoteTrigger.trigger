/**
 * RCAQuoteTrigger
 * Thin trigger on the native Quote object — all logic in handler.
 */
trigger RCAQuoteTrigger on Quote (
    before insert, before update,
    after insert,  after update
) {
    RCAQuoteTriggerHandler handler = new RCAQuoteTriggerHandler();

    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.onBeforeInsert(Trigger.new);
        if (Trigger.isUpdate) handler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.onAfterInsert(Trigger.new);
        if (Trigger.isUpdate) handler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
