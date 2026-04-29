@IsTest
private class OpportunityDemoDatesTest {

    @TestSetup
    static void makeData() {
        // Create a test opportunity with required fields
        Opportunity opp = new Opportunity(
            Name = 'Test Demo Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
    }

    @IsTest
    static void writeDemoDate_succeeds() {
        // Arrange
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Demo Opportunity' LIMIT 1];
        Date demoDate = Date.today().addDays(7);

        // Act
        Test.startTest();
        opp.demoDate__c = demoDate;
        update opp;
        Test.stopTest();

        // Assert
        Opportunity result = [SELECT Id, demoDate__c FROM Opportunity WHERE Id = :opp.Id WITH USER_MODE];
        System.assertEquals(demoDate, result.demoDate__c, 'Demo date should be written and readable');
    }

    @IsTest
    static void readDemoDate_withoutErrors() {
        // Arrange
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Demo Opportunity' LIMIT 1];
        Date demoDate = Date.today().addDays(14);
        opp.demoDate__c = demoDate;
        update opp;

        // Act
        Test.startTest();
        List<Opportunity> results = [SELECT Id, Name, demoDate__c FROM Opportunity WHERE Id = :opp.Id WITH USER_MODE];
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should retrieve opportunity');
        System.assertEquals(demoDate, results[0].demoDate__c, 'Demo date should be readable');
    }

    @IsTest
    static void demoDate_acceptsNullValue() {
        // Arrange
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Demo Opportunity' LIMIT 1];

        // Act
        Test.startTest();
        opp.demoDate__c = null;
        update opp;
        Test.stopTest();

        // Assert
        Opportunity result = [SELECT Id, demoDate__c FROM Opportunity WHERE Id = :opp.Id WITH USER_MODE];
        System.assertEquals(null, result.demoDate__c, 'Demo date should accept null (field is optional)');
    }

    @IsTest
    static void demoDate_governorLimitCheck() {
        // Arrange: Create bulk test opportunities
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opps.add(new Opportunity(
                Name = 'Bulk Test Opp ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;

        // Act
        Test.startTest();
        Integer queryCountBefore = Limits.getQueries();
        
        // Update all opportunities with demo dates
        Integer counter = 0;
        for (Opportunity opp : opps) {
            opp.demoDate__c = Date.today().addDays(counter++);
        }
        update opps;

        Integer queriesUsed = Limits.getQueries() - queryCountBefore;
        Test.stopTest();

        // Assert: ensure we're not querying excessively per record
        System.assert(queriesUsed < 10, 'Should not exceed reasonable query limits; used ' + queriesUsed + ' queries');
        
        // Verify data was persisted
        List<Opportunity> verified = [SELECT Id, demoDate__c FROM Opportunity WHERE Name LIKE 'Bulk Test Opp%' WITH USER_MODE];
        System.assertEquals(200, verified.size(), 'All bulk opportunities should be created');
    }
}
