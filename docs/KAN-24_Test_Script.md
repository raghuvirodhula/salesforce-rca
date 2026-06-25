# QA Test Script: KAN-24 BB1 Product & Ramp Pricing

This document details the functional QA manual validation scenarios and testing verification plans for **User Story KAN-24: Define BB1 Product and Ramp Pricing**.

---

## 1. Prerequisites for Testing
Ensure the following configurations are set up in the target testing sandbox:
1. **Custom Metadata:** The custom metadata type `BulkBillingRampSetting__mdt` is deployed.
2. **Metadata Records:** Ensure the active ramp settings exist in the org:
   * **Year 1:** `ProductCode__c = 'BB1'`, `YearNumber__c = 1`, `DiscountPercentage__c = 20.0`, `IsActive__c = true`
   * **Year 2:** `ProductCode__c = 'BB1'`, `YearNumber__c = 2`, `DiscountPercentage__c = 10.0`, `IsActive__c = true`
   * **Year 3:** `ProductCode__c = 'BB1'`, `YearNumber__c = 3`, `DiscountPercentage__c = 0.0`, `IsActive__c = true`
3. **Product Catalog:** A `Product2` record for "BB1 (Bulk Billing Product)" is created and active in the catalog.
4. **Pricebook:** A `PricebookEntry` for BB1 is configured in the standard price book with a list price of `$1,000.00` per year.
5. **Telephony/Integration User:** A tester account with the standard `RCA_Sales_User` permission set assigned.

---

## 2. Manual Test Cases (UAT Scenarios)

### Test Case 1: Product Catalog & Pricebook Validation (Positive Path)
* **Objective:** Verify that the BB1 product is active and has a valid pricebook entry in the Standard Pricebook.
* **Actor:** Sales Operations Specialist

| Step # | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| 1 | Log in to Salesforce and navigate to the **Products** tab. | Products home page loads. | |
| 2 | Search for the product code `BB1` and open the record page. | Product is found under Name: `"BB1 (Bulk Billing Product)"` and marked `Active = True`. | |
| 3 | Navigate to the **Related** tab and inspect the **Price Books** list. | A Pricebook Entry exists in the **Standard Price Book** with an Active List Price of `$1,000.00`. | |

---

### Test Case 2: Ramp Pricing TCV Calculation (Positive Path)
* **Objective:** Verify that a standard 3-year contract for the BB1 product applies the 20%/10%/0% ramp pricing rules correctly, calculating the correct Total Contract Value (TCV).
* **Actor:** Sales Operations Specialist

| Step # | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| 1 | Open the custom LWC Ramp Viewer on a Quote/Order page (or execute the invocable pricing flow). | The pricing widget loads, prompting for start date and term. | |
| 2 | Input the following variables:<br>- **Product Code:** `BB1`<br>- **Contract Start Date:** Today<br>- **Term (Years):** `3`<br>- **Base Annual Price:** `$1,000.00` | The preview updates dynamically in the interface. | |
| 3 | Verify Year 1 Pricing in the list. | **Year 1 Period:** Shows start date to next year's anniversary minus 1 day. <br>**Discount:** `20%`<br>**Net Period Price:** `$800.00` | |
| 4 | Verify Year 2 Pricing in the list. | **Year 2 Period:** Covering the second contract year.<br>**Discount:** `10%`<br>**Net Period Price:** `$900.00` | |
| 5 | Verify Year 3 Pricing in the list. | **Year 3 Period:** Covering the third contract year.<br>**Discount:** `0%`<br>**Net Period Price:** `$1,000.00` | |
| 6 | Verify Total Contract Value (TCV). | **TCV** is displayed as `$2,700.00` (computed as `$800.00 + $900.00 + $1,000.00`). | |

---

### Test Case 3: Pricing for Terms Exceeding the Configured Ramp (Positive / Boundary Path)
* **Objective:** Verify that contract terms longer than the configured metadata ramp (e.g. 5 years) correctly apply standard pricing (0% discount) for all years beyond Year 3.
* **Actor:** Sales Operations Specialist

| Step # | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| 1 | Open the pricing preview tool. | Screen active. | |
| 2 | Input the following:<br>- **Product Code:** `BB1`<br>- **Term (Years):** `5`<br>- **Base Annual Price:** `$1,000.00` | Preview calculates immediately. | |
| 3 | Verify Year 4 and Year 5 entries. | **Year 4 & Year 5:** Both show a `0%` discount and a Net Annual Price of `$1,000.00` (standard pricing is applied since no ramp discount is configured for years 4+). | |
| 4 | Verify Total Contract Value. | **TCV** is calculated as `$4,700.00` (comprising `$800.00 + $900.00 + $1,000.00 + $1,000.00 + $1,000.00`). | |

---

### Test Case 4: Invalid Contract Term Boundaries (Negative Path)
* **Objective:** Verify that input validation prevents terms outside the boundaries of 1 to 30 years.
* **Actor:** Sales Operations Specialist / API Engine

| Step # | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| 1 | Open the pricing tool and input a **Term (Years)** of `0`. | The system blocks the preview and raises a validation error: `"Term years must be between 1 and 30."` | |
| 2 | Input a **Term (Years)** of `31`. | The system blocks calculation and raises a validation error: `"Term years must be between 1 and 30."` | |

---

### Test Case 5: Negative Base Pricing Validation (Negative Path)
* **Objective:** Verify that input validation prevents calculations using negative price amounts.
* **Actor:** Sales Operations Specialist / API Engine

| Step # | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| 1 | Open the pricing tool and input a **Base Annual Price** of `-$100.00`. | The system blocks calculation and raises a validation error: `"Base annual price must be a non-negative number."` | |

---

### Test Case 6: Product Deactivation Edge Case (Regression Path)
* **Objective:** Verify that setting the BB1 product to inactive in the catalog blocks *new* pricing runs, but does not impact existing active calculation records.
* **Actor:** System Administrator

| Step # | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| 1 | Navigate to the **BB1** Product2 record and uncheck the `Active` checkbox. Save the record. | Product is successfully deactivated. | |
| 2 | Open an existing Onboarding Case or Order that was priced under BB1 prior to deactivation. | The existing TCV and JSON payload details remain saved and readable. | |
| 3 | Attempt to run a *new* pricing check for product code `BB1`. | The system blocks the new pricing transaction. | |
| 4 | Re-enable the `Active` checkbox on the BB1 product record. | Product is successfully reactivated, and new pricing preview runs successfully. | |
