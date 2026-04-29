/**
 * SetupProductCatalog.apex
 *
 * Seeds the native RCA Product Catalog with sample products
 * including ProductSellingModels for subscription and one-time selling motions.
 *
 * Run: sf apex run --file scripts/apex/SetupProductCatalog.apex --target-org rca-dev
 *
 * Native objects used:
 *   Product2                 - the product
 *   ProductSellingModel      - selling motion (Termed / Evergreen / OneTime)
 *   ProductSellingModelOption - links product to selling models
 *   PricebookEntry           - list price per pricebook
 */

Id stdPricebook = Test.getStandardPricebookId();

// ─── ProductSellingModels ──────────────────────────────────────────────────────
// In a real org these are configured declaratively in Setup → Revenue Cloud
// Here we create them programmatically for sandbox seeding.

ProductSellingModel monthlyModel = new ProductSellingModel(
    Name             = 'Monthly Subscription',
    SellingModelType = 'EvergreenSubscription',
    PricingTerm      = 1,           // months
    PricingTermUnit  = 'Months',
    Status           = 'Active'
);

ProductSellingModel annualModel = new ProductSellingModel(
    Name             = 'Annual Subscription',
    SellingModelType = 'TermedSubscription',
    PricingTerm      = 12,
    PricingTermUnit  = 'Months',
    Status           = 'Active'
);

ProductSellingModel oneTimeModel = new ProductSellingModel(
    Name             = 'One-Time Purchase',
    SellingModelType = 'OneTime',
    Status           = 'Active'
);

insert new List<ProductSellingModel>{ monthlyModel, annualModel, oneTimeModel };
System.debug('Inserted ProductSellingModels');

// ─── Products ──────────────────────────────────────────────────────────────────

List<Product2> products = new List<Product2>{
    new Product2(
        Name        = 'RCA Platform — Starter',
        ProductCode = 'RCA-STARTER',
        Family      = 'Subscription',
        IsActive    = true,
        Description = 'Core platform access up to 10 users'
    ),
    new Product2(
        Name        = 'RCA Platform — Professional',
        ProductCode = 'RCA-PRO',
        Family      = 'Subscription',
        IsActive    = true,
        Description = 'Full platform, unlimited users, advanced analytics'
    ),
    new Product2(
        Name        = 'Advanced Analytics Add-On',
        ProductCode = 'ADDON-ANALYTICS',
        Family      = 'Add-On',
        IsActive    = true,
        Description = 'Real-time revenue analytics and forecasting'
    ),
    new Product2(
        Name        = 'Implementation Services',
        ProductCode = 'PS-IMPL',
        Family      = 'Professional Services',
        IsActive    = true,
        Description = 'Fixed-fee implementation and onboarding package'
    )
};

insert products;
System.debug('Inserted ' + products.size() + ' products');

// ─── ProductSellingModelOptions ────────────────────────────────────────────────
// Links each product to its available selling models

List<ProductSellingModelOption> options = new List<ProductSellingModelOption>();

// Starter: monthly + annual
options.add(new ProductSellingModelOption(Product2Id=products[0].Id, ProductSellingModelId=monthlyModel.Id));
options.add(new ProductSellingModelOption(Product2Id=products[0].Id, ProductSellingModelId=annualModel.Id));

// Professional: monthly + annual
options.add(new ProductSellingModelOption(Product2Id=products[1].Id, ProductSellingModelId=monthlyModel.Id));
options.add(new ProductSellingModelOption(Product2Id=products[1].Id, ProductSellingModelId=annualModel.Id));

// Analytics Add-On: monthly only
options.add(new ProductSellingModelOption(Product2Id=products[2].Id, ProductSellingModelId=monthlyModel.Id));

// Professional Services: one-time only
options.add(new ProductSellingModelOption(Product2Id=products[3].Id, ProductSellingModelId=oneTimeModel.Id));

insert options;
System.debug('Inserted ' + options.size() + ' ProductSellingModelOptions');

// ─── PricebookEntries ──────────────────────────────────────────────────────────

List<PricebookEntry> pbes = new List<PricebookEntry>{
    new PricebookEntry(Pricebook2Id=stdPricebook, Product2Id=products[0].Id, UnitPrice=499.00,   IsActive=true),
    new PricebookEntry(Pricebook2Id=stdPricebook, Product2Id=products[1].Id, UnitPrice=1499.00,  IsActive=true),
    new PricebookEntry(Pricebook2Id=stdPricebook, Product2Id=products[2].Id, UnitPrice=299.00,   IsActive=true),
    new PricebookEntry(Pricebook2Id=stdPricebook, Product2Id=products[3].Id, UnitPrice=7500.00,  IsActive=true)
};

insert pbes;
System.debug('Inserted ' + pbes.size() + ' pricebook entries');
System.debug('✅ Product catalog setup complete');
