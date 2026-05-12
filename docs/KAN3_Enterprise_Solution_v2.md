# Executive Summary
Implemented the core product definition and ramp pricing logic for the **BB1 Bulk Billing** model. This foundation enables RTelco to offer property-level billing with automated year-over-year discounts (20% Y1, 10% Y2, 0% Y3+).

# Technical Design
- **Configuration Engine**: Utilizes `BulkBillingRampSetting__mdt` (Custom Metadata Type) for externalized, deployment-friendly logic.
- **Service Layer**: `BulkBillingService.cls` encapsulates the discount retrieval logic, providing a single point of failure and easy unit testing.
- **Data Model**: Configured to support standard Salesforce Product2 records while maintaining loose coupling with the pricing engine.

# Impacted Components
- **Custom Metadata**: `BulkBillingRampSetting__mdt`
- **Apex Classes**: `BulkBillingService`, `BulkBillingServiceTest`
- **Objects**: `Product2` (Reference)

# Deployment Plan
1. Deploy Custom Metadata Type definition.
2. Deploy Custom Metadata Records (Year 1, Year 2).
3. Deploy Apex Classes.
4. Verify metadata retrieval in the target environment.

# PR Summary
**Title**: feat: BB1 Product Definition and Ramp Pricing Engine
**Description**: Established the metadata-driven discount engine for the Bulk Billing model. Replaced hardcoded pricing logic with Custom Metadata to support enterprise scale and CI/CD portability.
