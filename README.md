# Salesforce ↔ External API Integration

Demonstrates how to connect Salesforce to an external REST API using a Named Credential and Apex HTTP callouts, with the API key kept in a protected custom setting instead of the code. Uses the OpenWeatherMap API to write current weather for each Account's billing city to a field on the Account.

---

## Business Problem

Consultants are often asked to integrate Salesforce with external systems — ERPs, weather APIs, payment gateways, shipping providers. This project shows the full integration pattern: authenticated callout, JSON parsing, error handling, and writing the result back to a Salesforce record.

---

## How It Works

```
Entry points
  • Flow:            "Refresh Account Weather" action (WeatherSyncAction, @InvocableMethod, List<Id>)
  • Apex (async):    System.enqueueJob(new WeatherSyncQueueable(accountIds))
  • Apex (one-off):  WeatherService.fetchAndSaveWeather(accountId, city)
        │
        ▼
WeatherSyncQueueable (Database.AllowsCallouts, with sharing, user mode)
  - reads BillingCity, max 50 callouts per job, chains a new job for the rest
        │
        ▼
WeatherService.callWeatherApi(city)
  key ← OpenWeatherMap_Settings__c.API_Key__c (protected custom setting; missing → exception, no callout)
  HttpRequest → callout:OpenWeatherMap (Named Credential → External Credential principal)
  GET https://api.openweathermap.org/data/2.5/weather?q={city}&units=metric&appid={key}
        │
        ├─ 200 OK + valid JSON → typed wrapper → summary text
        ├─ 404                 → WeatherServiceException("City not found: …")
        ├─ other status        → WeatherServiceException with the status code (no response body)
        ├─ timeout / network   → CalloutException wrapped in WeatherServiceException
        └─ malformed / missing fields → WeatherServiceException (no response body)
        │
        ▼
One bulk update of Account.Weather_Info__c (allOrNone = false: failed rows are logged, successful rows are kept)
```

### Where the API key lives

OpenWeatherMap only accepts the key as the `appid` query parameter. Salesforce does not let an
External Credential put a secret into the callout URL. In a Developer Edition org at API 68.0, a
`{!$Credential.OpenWeatherMap.apiKey}` merge field in the Apex endpoint was not substituted, and
the platform rejects `$Credential` in a Named Credential URL. So the key is stored in the
**protected hierarchy custom setting** `OpenWeatherMap_Settings__c.API_Key__c`. You enter it in
Setup, and it is never in the code, a method parameter or this repository. `WeatherService` reads
it at callout time and never logs it or the request URL. (The platform's own callout debug-log events can still show the full URL, so treat debug logs as sensitive.)

The callout still goes through the `OpenWeatherMap` Named Credential, so the host is set in Setup
and no Remote Site Setting is needed. A Named Credential must link an External Credential, so the
`OpenWeatherMap` External Credential (Custom protocol) has an empty `OpenWeatherMapKey` principal.
It holds no secret, but users need access to that principal to make the callout, and the
permission set grants it.

---

## Sample Output on Account

`Account.Weather_Info__c` (Text 255) is updated to:

```
Paris, FR | 18.5°C | light rain | Humidity: 72% | Wind: 4.2 m/s
```

---

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── WeatherService.cls          # Callout, typed JSON parsing, error handling, summary format
│   ├── WeatherSyncQueueable.cls    # Async bulk refresh (chunked callouts, partial-failure safe)
│   ├── WeatherSyncAction.cls       # @InvocableMethod for Flow, enqueues the Queueable
│   ├── WeatherCalloutMock.cls      # Test-only HttpCalloutMock (records requests, simulates timeout/404)
│   ├── WeatherTestAccess.cls       # Test-only: Platform user with the permission set, fake API key
│   ├── WeatherServiceTest.cls      # Service tests
│   └── WeatherSyncTest.cls         # Queueable + invocable tests
├── externalCredentials/
│   └── OpenWeatherMap.externalCredential-meta.xml   # Custom protocol, empty named principal, no secret
├── namedCredentials/
│   └── OpenWeatherMap.namedCredential-meta.xml      # https://api.openweathermap.org
├── objects/
│   ├── Account/fields/Weather_Info__c.field-meta.xml
│   └── OpenWeatherMap_Settings__c/                   # Protected hierarchy custom setting, API_Key__c
└── permissionsets/
    └── Weather_Integration_User.permissionset-meta.xml
```

---

## Setup

Requires an org that supports Apex (for example a Developer Edition org).

```bash
git clone https://github.com/ridanajjari/salesforce-api-integration.git
cd salesforce-api-integration
sf org login web --alias my-org

# 1. Deploy (field, custom setting, credentials, permission set and Apex)
sf project deploy start --source-dir force-app --target-org my-org

# 2. Give your user access to the classes, the field and the External Credential principal
sf org assign permset --name Weather_Integration_User --target-org my-org

# 3. Run the Apex tests
sf apex run test --target-org my-org --class-names WeatherServiceTest --class-names WeatherSyncTest --code-coverage --result-format human --wait 30
```

4. Enter your OpenWeatherMap API key in Setup (never commit it):
   Setup → Custom Settings → **OpenWeatherMap Settings** → Manage → New (default organization
   level value) → API Key = `<your key>` → Save.

5. Try it from Anonymous Apex:

```apex
// One account, synchronous
WeatherService.fetchAndSaveWeather('YOUR_ACCOUNT_ID', 'Paris');

// Many accounts, async (uses each Account's BillingCity)
System.enqueueJob(new WeatherSyncQueueable(new List<Id>{ 'YOUR_ACCOUNT_ID' }));
```

Or add the **Refresh Account Weather** action to a Flow and pass it Account Ids.

---

## Testing

- ✅ Deployed to a Developer Edition org at API 68.0 (2026-11-12); 18/18 Apex test methods passing
  (`WeatherServiceTest` 13, `WeatherSyncTest` 5; the runner reports 19 because it also counts the
  `@TestSetup` method). Coverage as measured: WeatherService 97%, WeatherSyncQueueable 96%,
  WeatherSyncAction 100%.
- ✅ The tests cover:
  - the request: GET, the `callout:OpenWeatherMap` endpoint, the URL-encoded city, `appid`
  - the key read from the custom setting, and a missing key (no callout made)
  - parsing, and missing optional blocks
  - 404, and non-200 status without leaking the body
  - callout timeout
  - malformed, empty and incomplete JSON, and a blank city
  - the synchronous Account update
  - Queueable end-to-end, partial failure, chunking + chaining
  - the invocable action

  Tests that touch Account run as a Salesforce Platform user with only the
  `Weather_Integration_User` permission set.

- ✅ Live callout check (same org): with a dummy key in the custom setting,
  `WeatherService.callWeatherApi('Paris')` reached OpenWeatherMap through the Named Credential
  and got HTTP 401, surfaced as `Weather API returned HTTP 401`. Without the permission set the
  callout failed with "couldn't access the credential(s)". The dummy key and the temporary
  assignment were removed afterwards. A real key was not used.
- ✅ Offline checks passing: `npm run lint`, `npm run prettier:verify`,
  `npx prettier --check "force-app/**/*.{cls,trigger}"` (Apex parses), XML well-formed.

---

## Key Salesforce Concepts Demonstrated

- **Named Credential + protected custom setting** — endpoint managed in Setup, API key kept out of code and the repo; callout access granted through a permission set
- **Queueable with `Database.AllowsCallouts`** — callouts chunked under the per-transaction limit, chained jobs, one bulk DML after all callouts
- **Partial-failure handling** — `Database.update(records, false, AccessLevel.USER_MODE)`
- **`@InvocableMethod`** — Flow entry point that enqueues the async job
- **Typed JSON parsing** — `JSON.deserialize` into wrapper classes with null guards
- **`HttpCalloutMock`** — request assertions, simulated timeout, malformed bodies, 404 for selected cities
- **Security** — `with sharing`, `WITH USER_MODE` queries, user-mode DML, no response bodies in exception messages

---

## Author

**Rida Najjari** — Salesforce Consultant, Developer & Administrator

4x Salesforce Certified: Platform Administrator · Platform App Builder · Platform Developer I · Associate

- LinkedIn: [linkedin.com/in/rida-najjari](https://www.linkedin.com/in/rida-najjari)
- GitHub: [github.com/ridanajjari](https://github.com/ridanajjari)
