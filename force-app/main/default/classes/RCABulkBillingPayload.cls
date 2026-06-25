/**
 * RCABulkBillingPayload
 *
 * Strongly-typed DTOs for the BB1 ramp pricing payload sent downstream
 * to Order Orchestration / Zuora. JSON-serializable; no SObjects on the wire.
 *
 * API 66.0  (Spring '26)
 */
public with sharing class RCABulkBillingPayload {

    /** One ramp tier — what year, what discount, what net annual price. */
    public class RampTier {
        @AuraEnabled public Integer yearNumber;
        @AuraEnabled public Decimal discountPercentage;
        @AuraEnabled public Decimal netAnnualPrice;
        @AuraEnabled public Date    periodStartDate;
        @AuraEnabled public Date    periodEndDate;

        public RampTier() {}

        public RampTier(Integer yearNumber, Decimal discountPercentage,
                        Decimal netAnnualPrice, Date periodStart, Date periodEnd) {
            this.yearNumber         = yearNumber;
            this.discountPercentage = discountPercentage;
            this.netAnnualPrice     = netAnnualPrice;
            this.periodStartDate    = periodStart;
            this.periodEndDate      = periodEnd;
        }
    }

    /** Top-level envelope for downstream consumers. */
    public class Envelope {
        @AuraEnabled public String          productCode;
        @AuraEnabled public Id              contextRecordId;
        @AuraEnabled public Date            contractStartDate;
        @AuraEnabled public Integer         termYears;
        @AuraEnabled public Decimal         baseAnnualPrice;
        @AuraEnabled public List<RampTier>  tiers;
        @AuraEnabled public Decimal         totalContractValue;

        public Envelope() {
            this.tiers = new List<RampTier>();
        }

        public String toJson() {
            return JSON.serialize(this, /*suppressApexObjectNulls*/ true);
        }
    }
}
