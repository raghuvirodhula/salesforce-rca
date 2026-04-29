/**
 * SetupPricingData.apex
 *
 * Creates a native RCA PriceAdjustmentSchedule with volume tiers
 * (the replacement for CPQ discount schedules).
 *
 * Native objects:
 *   PriceAdjustmentSchedule  - the schedule (e.g. 'Volume Discount')
 *   PriceAdjustmentTier      - individual break-points
 *
 * Run: sf apex run --file scripts/apex/SetupPricingData.apex --target-org rca-dev
 */

// Create a volume-based discount schedule
PriceAdjustmentSchedule volumeSchedule = new PriceAdjustmentSchedule(
    Name              = 'Standard Volume Discount',
    AdjustmentType    = 'DiscountPercentage',
    IsActive          = true,
    Description       = 'Tiered volume discounts: 5% at 10+, 10% at 25+, 15% at 50+'
);
insert volumeSchedule;

// Create the tiers
List<PriceAdjustmentTier> tiers = new List<PriceAdjustmentTier>{
    new PriceAdjustmentTier(
        PriceAdjustmentScheduleId = volumeSchedule.Id,
        TierStartValue            = 1,
        TierEndValue              = 9,
        AdjustmentValue           = 0      // No discount < 10 units
    ),
    new PriceAdjustmentTier(
        PriceAdjustmentScheduleId = volumeSchedule.Id,
        TierStartValue            = 10,
        TierEndValue              = 24,
        AdjustmentValue           = 5      // 5% discount 10–24 units
    ),
    new PriceAdjustmentTier(
        PriceAdjustmentScheduleId = volumeSchedule.Id,
        TierStartValue            = 25,
        TierEndValue              = 49,
        AdjustmentValue           = 10     // 10% discount 25–49 units
    ),
    new PriceAdjustmentTier(
        PriceAdjustmentScheduleId = volumeSchedule.Id,
        TierStartValue            = 50,
        TierEndValue              = 999999,
        AdjustmentValue           = 15     // 15% discount 50+ units
    )
};

insert tiers;
System.debug('✅ PriceAdjustmentSchedule and ' + tiers.size() + ' tiers created');
