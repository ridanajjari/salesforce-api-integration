# Salesforce ↔ External API Integration

Demonstrates how to connect Salesforce to an external REST API using an External Credential, a Named Credential and Apex HTTP callouts. Uses the OpenWeatherMap API to write current weather for each Account's billing city to a field on the Account.

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
  HttpRequest → callout:OpenWeatherMap (Named Credential)
             → OpenWeatherMap External Credential (named principal holds the key)
  GET https://api.openweathermap.org/data/2.5/weather?q={city}&units=metric&appid={!$Credential.OpenWeatherMap.apiKey}
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

OpenWeatherMap expects the key as the `appid` query parameter. The key is stored only in the
org, on the `OpenWeatherMapKey` named principal of the `OpenWeatherMap` External Credential
(Custom authentication protocol, parameter `apiKey`). The Apex request URL contains the merge
field `{!$Credential.OpenWeatherMap.apiKey}`, which the platform replaces when the callout goes
through the `OpenWeatherMap` Named Credential. The key is not in the code, not a method
parameter, and not in this repository.

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
│   ├── WeatherServiceTest.cls      # Service tests
│   └── WeatherSyncTest.cls         # Queueable + invocable tests
├── externalCredentials/
│   └── OpenWeatherMap.externalCredential-meta.xml   # Custom protocol, named principal, no secret
├── namedCredentials/
│   └── OpenWeatherMap.namedCredential-meta.xml      # https://api.openweathermap.org
├── objects/Account/fields/
│   └── Weather_Info__c.field-meta.xml
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

# 1. Deploy (field, credentials, permission set and Apex)
sf project deploy start --source-dir force-app --target-org my-org

# 2. Give your user access to the classes, the field and the External Credential principal
sf org assign permset --name Weather_Integration_User --target-org my-org

# 3. Run the Apex tests
sf apex run test --target-org my-org --class-names WeatherServiceTest --class-names WeatherSyncTest --code-coverage --result-format human --wait 30
```

4. Enter your OpenWeatherMap API key in Setup (never commit it):
   Setup → Named Credentials → External Credentials → **OpenWeatherMap** → Principals →
   **OpenWeatherMapKey** → Edit → Authentication Parameters → Add: Name `apiKey`, Value `<your key>` → Save.

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

- ✅ Apex tests written: 16 test methods (`WeatherServiceTest`, `WeatherSyncTest`) covering the
  request (GET, `callout:OpenWeatherMap` endpoint, URL-encoded city, `appid` merge field),
  successful parsing, missing optional blocks, 404, non-200 status without leaking the body,
  callout timeout, malformed / empty / incomplete JSON, blank city, synchronous Account update,
  Queueable end-to-end, partial failure, chunking + chaining, and the invocable action.
- ✅ Offline checks passing (2026-11-12): Apex parses (prettier-plugin-apex), ESLint, Prettier,
  XML well-formed:
  `npm run lint`, `npm run prettier:verify`, `npx prettier --check "force-app/**/*.{cls,trigger}"`.
- ✅ Non-Apex metadata (Weather_Info__c field, OpenWeatherMap External and Named Credential,
  permission set without the Apex class entries) deployed to a Salesforce org at API 68.0.
- ⏳ Apex deployment, test execution and coverage: pending a run in a Developer Edition org.

---

## Key Salesforce Concepts Demonstrated

- **External Credential + Named Credential** — API key kept out of code and the repo, entered in Setup on a named principal; access granted through a permission set
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
