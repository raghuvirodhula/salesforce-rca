> **AI-Generated Content Disclaimer:** This document was created with the assistance of AI (Claude Code). AI can make mistakes, hallucinate commands, or reference outdated information. Verify all instructions against official documentation before use, especially in production environments. When in doubt, consult the [AWS Bedrock docs](https://docs.aws.amazon.com/bedrock/), the [Claude Code docs](https://code.claude.com/docs), and your AWS administrator.

# Salesforce Conventions

This file is auto-loaded when editing Salesforce source files (`force-app/**`, `*.cls`, `*.js` in `lwc/`).

---

## Naming Conventions

### Apex

| Type | Convention | Example |
|------|-----------|---------|
| Class | PascalCase + type suffix | `AccountService`, `AccountTriggerHandler` |
| Test class | Match production class + `Test` | `AccountServiceTest` |
| Trigger | PascalCase + `Trigger` | `AccountTrigger` |
| Interface | PascalCase + `I` prefix | `IAccountService` |
| Method | camelCase | `getAccountById`, `processOpportunities` |
| Variable | camelCase | `accountList`, `opportunityMap` |
| Constant | SCREAMING_SNAKE_CASE | `MAX_BATCH_SIZE`, `DEFAULT_STATUS` |
| Custom exception | PascalCase + `Exception` | `AccountNotFoundException` |

### LWC

| Type | Convention | Example |
|------|-----------|---------|
| Component directory | kebab-case | `account-tile`, `opportunity-card` |
| JS class | PascalCase (auto-generated) | `AccountTile` |
| `@api` property | camelCase | `accountId`, `recordData` |
| `@track` (if used) | camelCase | `isLoading`, `errorMessage` |
| Custom event name | kebab-case | `accountselect`, `recordchange` |
| CSS class | kebab-case | `account-name`, `status-badge` |

---

## Apex Patterns

### Trigger Architecture

Never put logic in a trigger. Use a handler pattern:

```apex
// AccountTrigger.trigger — thin dispatcher only
trigger AccountTrigger on Account (before insert, before update, after insert, after update) {
    AccountTriggerHandler handler = new AccountTriggerHandler();
    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.onBeforeInsert(Trigger.new);
        if (Trigger.isUpdate) handler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.onAfterInsert(Trigger.new);
        if (Trigger.isUpdate) handler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
```

### Bulkification (Non-Negotiable)

Never SOQL or DML inside a loop. Always collect into lists/maps first:

```apex
// BAD — SOQL in loop
for (Account acc : accounts) {
    Contact c = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1]; // Governor violation
    acc.Primary_Contact__c = c.Id;
}

// GOOD — bulk query first
Map<Id, Contact> contactsByAccount = new Map<Id, Contact>();
for (Contact c : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds]) {
    contactsByAccount.put(c.AccountId, c);
}
for (Account acc : accounts) {
    if (contactsByAccount.containsKey(acc.Id)) {
        acc.Primary_Contact__c = contactsByAccount.get(acc.Id).Id;
    }
}
```

### Security: WITH USER_MODE

Use `WITH USER_MODE` for queries in service classes unless there is a documented reason for elevated access:

```apex
// Default — respects user's FLS and sharing rules
List<Account> accounts = [SELECT Id, Name FROM Account WITH USER_MODE];

// Elevated access — must have a comment explaining why
// Running as system because this is a background job processing all records
List<Account> allAccounts = [SELECT Id FROM Account WITH SYSTEM_MODE];
```

### FLS Enforcement

Before DML operations that write user-provided field values:

```apex
// Check field-level security before update
SObjectField nameField = Account.SObjectType.fields.getMap().get('Name');
if (!nameField.getDescribe().isUpdateable()) {
    throw new SecurityException('Insufficient permissions to update Account.Name');
}
```

### Exception Handling

Define custom exceptions per domain:

```apex
public class AccountService {
    public class AccountNotFoundException extends Exception {}
    public class AccountValidationException extends Exception {}

    public static Account getAccountById(Id accountId) {
        List<Account> results = [SELECT Id, Name FROM Account WHERE Id = :accountId WITH USER_MODE];
        if (results.isEmpty()) {
            throw new AccountNotFoundException('Account not found: ' + accountId);
        }
        return results[0];
    }
}
```

---

## LWC Patterns

### Property Binding

Prefer `@wire` over imperative calls for data that can be cached:

```javascript
// GOOD — reactive, cached
@wire(getRecord, { recordId: '$recordId', fields: FIELDS })
account;

// Use imperative only when you need to control when the call fires
handleSave() {
    updateAccount({ accountId: this.recordId, data: this.formData })
        .then(() => { /* success */ })
        .catch(error => { this.error = error; });
}
```

### Error Handling

Always handle both wire error and imperative catch states:

```javascript
@wire(getRecord, { recordId: '$recordId', fields: FIELDS })
wiredAccount({ error, data }) {
    if (data) {
        this.account = data;
        this.error = undefined;
    } else if (error) {
        this.error = error;
        this.account = undefined;
    }
}
```

### Event Communication

Use custom events for child-to-parent communication. Never reach into a child component's internals:

```javascript
// Child — dispatch event
handleSelect() {
    this.dispatchEvent(new CustomEvent('accountselect', {
        detail: { accountId: this.accountId }
    }));
}

// Parent HTML
<c-account-tile onaccountselect={handleAccountSelect}></c-account-tile>

// Parent JS
handleAccountSelect(event) {
    this.selectedAccountId = event.detail.accountId;
}
```

### No Hardcoded IDs or URLs

```javascript
// BAD
const ORG_ID = '00Dxx0000000000';
const API_URL = 'https://myorg.my.salesforce.com/services/data/v60.0';

// GOOD — use Named Credentials for external URLs, wire for Salesforce data
import { getRecord } from 'lightning/uiRecordApi';
```

---

## Metadata Conventions

- **API version:** Use the current org API version for all new metadata. Check `sfdx-project.json`.
- **Profiles vs Permission Sets:** New permissions go in Permission Sets, not Profiles.
- **Custom fields:** Use `__c` suffix (automatically added by Salesforce). Include a description.
- **Custom objects:** Use `__c` suffix. Include a description and help text on all fields.
- **Flows:** Named as `ObjectName_ActionDescription` (e.g., `Account_UpdateStatus`).

---

## SOQL Best Practices

```apex
// Include field-level context
List<Account> accounts = [
    SELECT Id, Name, BillingCity, AnnualRevenue
    FROM Account
    WHERE IsDeleted = false
      AND AnnualRevenue > 0
    WITH USER_MODE
    ORDER BY Name ASC
    LIMIT 200
];

// Use bind variables — never string concatenation
String searchTerm = '%' + userInput + '%';
List<Account> results = [SELECT Id, Name FROM Account WHERE Name LIKE :searchTerm WITH USER_MODE];
// NOT: 'WHERE Name LIKE \'%' + userInput + '%\'' — SOQL injection risk
```

---

## What AI Gets Wrong in Salesforce

Watch for these AI patterns in code review:

- **Missing `WITH USER_MODE`** — AI defaults to system-level access
- **SOQL in loops** — AI generates readable but unscalable code
- **`SeeAllData=true` in tests** — AI copies patterns from Stack Overflow examples
- **Hardcoded IDs** — AI uses placeholder IDs that work in one org only
- **Missing bulkification** — AI optimizes for single-record clarity
- **Generic exception catches** — AI uses `catch(Exception e)` instead of specific types
- **Unused imports in LWC** — AI scaffolds imports it doesn't use
