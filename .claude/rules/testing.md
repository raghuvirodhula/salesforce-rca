> **AI-Generated Content Disclaimer:** This document was created with the assistance of AI (Claude Code). AI can make mistakes, hallucinate commands, or reference outdated information. Verify all instructions against official documentation before use, especially in production environments. When in doubt, consult the [AWS Bedrock docs](https://docs.aws.amazon.com/bedrock/), the [Claude Code docs](https://code.claude.com/docs), and your AWS administrator.

# Testing Standards

This file is auto-loaded when editing test files (`__tests__/**`, `*.test.js`, `*.test.ts`, `*.spec.js`, `*.spec.ts`, `*Test.cls`).

---

## Core Principle

**Tests must assert behavior, not implementation.** A test that passes even when the code is broken is not a test — it's false confidence.

---

## LWC Tests (Jest)

### Setup

Tests live in `__tests__/` directories adjacent to the component they test.

```
force-app/main/default/lwc/
  accountTile/
    accountTile.js
    accountTile.html
    __tests__/
      accountTile.test.js
```

Run tests:

```bash
npx jest
# or with coverage:
npx jest --coverage
```

### Required Structure

```javascript
import { createElement } from 'lwc';
import AccountTile from 'c/accountTile';

describe('c-account-tile', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('displays account name', () => {
        const element = createElement('c-account-tile', { is: AccountTile });
        element.account = { Id: '001xx000001gErI', Name: 'Acme Corp' };
        document.body.appendChild(element);

        const nameEl = element.shadowRoot.querySelector('.account-name');
        expect(nameEl.textContent).toBe('Acme Corp');
    });
});
```

### What to Test

- **Rendered output:** Does the component display the correct data?
- **User interactions:** Click handlers, input changes, form submissions
- **Wire adapter responses:** Test both success and error states
- **Property changes:** Does the component react correctly when `@api` properties change?
- **Conditional rendering:** Do elements appear/disappear based on state?
- **Event emission:** Does the component dispatch the right custom events?

### Anti-Patterns

```javascript
// BAD: assertion-free test
it('renders component', () => {
    const element = createElement('c-account-tile', { is: AccountTile });
    document.body.appendChild(element);
    // No assertions — this always passes
});

// BAD: testing implementation details
it('calls fetchAccount', () => {
    // Testing that a private method was called — brittle
});

// GOOD: testing behavior
it('shows error message when account load fails', () => {
    const element = createElement('c-account-tile', { is: AccountTile });
    document.body.appendChild(element);
    getRecord.mockRejectedValue(new Error('Not found'));
    return Promise.resolve().then(() => {
        const error = element.shadowRoot.querySelector('.error-message');
        expect(error).not.toBeNull();
        expect(error.textContent).toContain('Not found');
    });
});
```

### Skip Markers

`test.skip()`, `it.skip()`, `describe.skip()`, `xit()`, `xdescribe()`, and `test.todo()` require a comment explaining why and a JIRA ticket number:

```javascript
// JIRA-123: Wire adapter mock not yet available for CustomObjectService
test.skip('loads custom object data', () => { ... });
```

---

## Apex Tests

### Required Structure

Every Apex class must have a corresponding `*Test.cls`:

```apex
@IsTest
private class AccountServiceTest {

    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
    }

    @IsTest
    static void getAccountById_returnsAccount() {
        Account expected = [SELECT Id, Name FROM Account LIMIT 1];

        Test.startTest();
        Account result = AccountService.getAccountById(expected.Id);
        Test.stopTest();

        System.assertEquals(expected.Id, result.Id, 'Should return correct account');
        System.assertEquals('Test Account', result.Name, 'Should return account with correct name');
    }

    @IsTest
    static void getAccountById_throwsOnInvalidId() {
        Boolean exceptionThrown = false;
        try {
            AccountService.getAccountById('invalid');
        } catch (AccountService.AccountNotFoundException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Should throw AccountNotFoundException for invalid ID');
    }
}
```

### Required Practices

- **`@TestSetup`** for data creation — runs once per test class, not per method
- **`Test.startTest()` / `Test.stopTest()`** around the code under test — resets governor limits and processes async work
- **`System.assertEquals(expected, actual, message)`** — always include a message for diagnostic clarity
- **Both happy path and error path** — every public method needs at least one negative test
- **Never `SeeAllData=true`** — creates org dependency, breaks in scratch orgs. Exception requires a documented, approved reason.

### Governor Limit Testing

When testing bulk operations, always test with >1 record:

```apex
@IsTest
static void processAccounts_bulkifiesCorrectly() {
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < 200; i++) {
        accounts.add(new Account(Name = 'Test Account ' + i));
    }
    insert accounts;

    Test.startTest();
    Integer queryCount = Limits.getQueries();
    AccountService.processAll(accounts);
    Integer queriesUsed = Limits.getQueries() - queryCount;
    Test.stopTest();

    System.assert(queriesUsed < 5, 'Should not query per-record; used ' + queriesUsed + ' queries');
}
```

### What Constitutes a Meaningful Apex Assertion

```apex
// BAD: assertion-free
@IsTest
static void testInsertAccount() {
    Account acc = new Account(Name = 'Test');
    insert acc;
    // No assertion — passes even if insert silently fails
}

// BAD: tests that an object is not null
System.assertNotEquals(null, result); // Nearly always passes

// GOOD: tests specific state
System.assertEquals('Active', account.Status__c, 'Newly created account should be Active');
System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :account.Id],
    'Should create one follow-up task');
```

---

## Coverage Requirements

Salesforce requires 75% Apex coverage for deployment to production. We target higher:

- **Minimum for deployment:** 75% org-wide
- **Our target:** 85%+ per class, 90%+ for service/handler classes
- **Not the goal:** 100% coverage with meaningless assertions. Coverage is a floor, not a measure of quality.

---

## Cross-Cutting Test Rules

1. **No `@IsTest(SeeAllData=true)`** unless documented with a JIRA ticket and approval
2. **No hardcoded IDs** in tests — always use `@TestSetup` data or dynamic queries
3. **Clean up in Jest** — always clear `document.body` in `afterEach`
4. **Mock external calls** — Apex callouts use `Test.setMock(HttpCalloutMock.class, ...)`, not real endpoints
5. **Test the integration** — unit tests are not enough for trigger handlers; include integration-level scenarios
