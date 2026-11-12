/**
 * Asynchronously refreshes Account.Weather_Info__c for a list of Account Ids,
 * using each Account's BillingCity.
 *
 * - Database.AllowsCallouts: one OpenWeatherMap callout per Account.
 * - Processes at most MAX_CALLOUTS_PER_JOB Accounts per execution (well under
 *   the 100-callout limit) and chains a new job for the remaining Ids.
 * - All callouts happen first, then one bulk update (callouts are not allowed
 *   after DML in the same transaction).
 * - Partial failures: an Account whose callout fails is skipped and logged;
 *   the update uses allOrNone=false so one bad row does not roll back the rest.
 * - Runs with sharing; the query and update run in user mode, so the enqueuing
 *   user's record access and FLS apply.
 */
public with sharing class WeatherSyncQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible
    private static final Integer MAX_CALLOUTS_PER_JOB = 50;

    // Set instead of enqueuing when chaining from a test (chained jobs cannot be enqueued in tests).
    @TestVisible
    private static List<Id> chainedIdsInTest;

    private final List<Id> accountIds;

    @TestVisible
    private Integer updatedCount = 0;
    @TestVisible
    private Integer failedCount = 0;

    public WeatherSyncQueueable(List<Id> accountIds) {
        // De-duplicate and drop nulls, keeping the original order.
        Set<Id> seen = new Set<Id>();
        this.accountIds = new List<Id>();
        if (accountIds != null) {
            for (Id accountId : accountIds) {
                if (accountId != null && seen.add(accountId)) {
                    this.accountIds.add(accountId);
                }
            }
        }
    }

    public Boolean hasWork() {
        return !accountIds.isEmpty();
    }

    public void execute(QueueableContext context) {
        List<Id> currentIds = new List<Id>();
        List<Id> remainingIds = new List<Id>();
        for (Id accountId : accountIds) {
            if (currentIds.size() < MAX_CALLOUTS_PER_JOB) {
                currentIds.add(accountId);
            } else {
                remainingIds.add(accountId);
            }
        }

        List<Account> toUpdate = new List<Account>();
        for (Account acc : [
            SELECT Id, BillingCity
            FROM Account
            WHERE Id IN :currentIds AND BillingCity != NULL
            WITH USER_MODE
        ]) {
            try {
                WeatherService.WeatherResult result = WeatherService.callWeatherApi(acc.BillingCity);
                toUpdate.add(new Account(Id = acc.Id, Weather_Info__c = WeatherService.formatSummary(result)));
            } catch (WeatherService.WeatherServiceException e) {
                failedCount++;
                System.debug(LoggingLevel.WARN, 'Weather refresh failed for ' + acc.Id + ': ' + e.getMessage());
            }
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> results = Database.update(toUpdate, false, AccessLevel.USER_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    updatedCount++;
                } else {
                    failedCount++;
                    System.debug(
                        LoggingLevel.WARN,
                        'Weather update failed for ' + toUpdate[i].Id + ': ' + results[i].getErrors()[0].getMessage()
                    );
                }
            }
        }

        if (!remainingIds.isEmpty()) {
            if (Test.isRunningTest()) {
                chainedIdsInTest = remainingIds;
            } else {
                System.enqueueJob(new WeatherSyncQueueable(remainingIds));
            }
        }
    }
}
