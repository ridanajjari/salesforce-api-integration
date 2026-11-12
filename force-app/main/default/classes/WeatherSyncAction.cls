/**
 * Flow / Process entry point: refresh weather for the given Accounts.
 * Callouts cannot run in the Flow transaction (it may already have done DML),
 * so this only enqueues one WeatherSyncQueueable for all Ids it receives.
 */
public with sharing class WeatherSyncAction {
  @InvocableMethod(
    label='Refresh Account Weather'
    description='Enqueues a job that fetches current weather for each Account BillingCity and writes it to Weather Info.'
    category='Weather'
  )
  public static void refreshWeather(List<Id> accountIds) {
    if (accountIds == null || accountIds.isEmpty()) {
      return;
    }
    WeatherSyncQueueable job = new WeatherSyncQueueable(accountIds);
    if (!job.hasWork()) {
      return;
    }
    System.enqueueJob(job);
  }
}
