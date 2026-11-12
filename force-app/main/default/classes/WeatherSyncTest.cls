@IsTest
private class WeatherSyncTest {
  private static final String PARIS_SUMMARY = 'Paris, FR | 18.5°C | light rain | Humidity: 72% | Wind: 4.2 m/s';

  @TestSetup
  static void createUser() {
    WeatherTestAccess.createIntegrationUser();
  }

  @IsTest
  static void queueableUpdatesAccountsWithCity() {
    System.runAs(WeatherTestAccess.integrationUser()) {
      Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());
      Account withCity = new Account(
        Name = 'Acme France',
        BillingCity = 'Paris'
      );
      Account noCity = new Account(Name = 'No City Ltd');
      insert new List<Account>{ withCity, noCity };

      Test.startTest();
      System.enqueueJob(
        new WeatherSyncQueueable(new List<Id>{ withCity.Id, noCity.Id })
      );
      Test.stopTest();

      Map<Id, Account> accounts = new Map<Id, Account>(
        [SELECT Weather_Info__c FROM Account]
      );
      Assert.areEqual(
        PARIS_SUMMARY,
        accounts.get(withCity.Id).Weather_Info__c,
        'Account with a city is updated'
      );
      Assert.isNull(
        accounts.get(noCity.Id).Weather_Info__c,
        'Account without a city is skipped'
      );
    }
  }

  @IsTest
  static void partialFailureKeepsSuccessfulRows() {
    System.runAs(WeatherTestAccess.integrationUser()) {
      WeatherCalloutMock mock = new WeatherCalloutMock();
      mock.notFoundCities.add('Atlantis');
      Test.setMock(HttpCalloutMock.class, mock);
      Account good = new Account(Name = 'Good', BillingCity = 'Paris');
      Account bad = new Account(Name = 'Bad', BillingCity = 'Atlantis');
      insert new List<Account>{ good, bad };

      WeatherSyncQueueable job = new WeatherSyncQueueable(
        new List<Id>{ good.Id, bad.Id }
      );
      Test.startTest();
      job.execute(null);
      Test.stopTest();

      Assert.areEqual(1, job.updatedCount, 'One Account updated');
      Assert.areEqual(1, job.failedCount, 'One Account failed');
      Map<Id, Account> accounts = new Map<Id, Account>(
        [SELECT Weather_Info__c FROM Account]
      );
      Assert.areEqual(
        PARIS_SUMMARY,
        accounts.get(good.Id).Weather_Info__c,
        'Successful row is saved'
      );
      Assert.isNull(
        accounts.get(bad.Id).Weather_Info__c,
        'Failed row is left unchanged'
      );
    }
  }

  @IsTest
  static void largeInputIsChunkedAndChained() {
    System.runAs(WeatherTestAccess.integrationUser()) {
      Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());
      Integer total = WeatherSyncQueueable.MAX_CALLOUTS_PER_JOB + 2;
      List<Account> accounts = new List<Account>();
      for (Integer i = 0; i < total; i++) {
        accounts.add(new Account(Name = 'Acct ' + i, BillingCity = 'Paris'));
      }
      insert accounts;
      List<Id> ids = new List<Id>(new Map<Id, Account>(accounts).keySet());

      WeatherSyncQueueable job = new WeatherSyncQueueable(ids);
      Test.startTest();
      job.execute(null);
      Integer calloutsUsed = Limits.getCallouts();
      Test.stopTest();

      Assert.areEqual(
        WeatherSyncQueueable.MAX_CALLOUTS_PER_JOB,
        calloutsUsed,
        'Callouts capped per job'
      );
      Assert.areEqual(
        WeatherSyncQueueable.MAX_CALLOUTS_PER_JOB,
        job.updatedCount,
        'First chunk updated'
      );
      Assert.areEqual(
        2,
        WeatherSyncQueueable.chainedIdsInTest.size(),
        'Remaining Ids passed to the next job'
      );
    }
  }

  @IsTest
  static void invocableEnqueuesOneJobAndUpdates() {
    System.runAs(WeatherTestAccess.integrationUser()) {
      Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());
      Account acc = new Account(Name = 'Acme France', BillingCity = 'Paris');
      insert acc;

      Test.startTest();
      WeatherSyncAction.refreshWeather(new List<Id>{ acc.Id, acc.Id, null });
      Assert.areEqual(1, Limits.getQueueableJobs(), 'Exactly one job enqueued');
      Test.stopTest();

      Account updated = [
        SELECT Weather_Info__c
        FROM Account
        WHERE Id = :acc.Id
      ];
      Assert.areEqual(
        PARIS_SUMMARY,
        updated.Weather_Info__c,
        'Invocable path updates the Account'
      );
    }
  }

  @IsTest
  static void invocableIgnoresEmptyInput() {
    System.runAs(WeatherTestAccess.integrationUser()) {
      Test.startTest();
      WeatherSyncAction.refreshWeather(new List<Id>());
      WeatherSyncAction.refreshWeather(new List<Id>{ null });
      Assert.areEqual(0, Limits.getQueueableJobs(), 'No job for empty input');
      Test.stopTest();
    }
  }
}
