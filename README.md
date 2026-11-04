# Salesforce ↔ External API Integration

Demonstrates how to connect Salesforce to an external REST API using Named Credentials and Apex HTTP callouts. Uses the OpenWeatherMap API to enrich Account records with real-time weather data for the account's city.

---

## Business Problem

Consultants are often asked to integrate Salesforce with external systems — ERPs, weather APIs, payment gateways, shipping providers. This project shows the full integration pattern: authenticated callout, JSON parsing, error handling, and writing the result back to a Salesforce record.

---

## How It Works

```
User triggers WeatherService.fetchAndSaveWeather(accountId, city, apiKey)
        │
        ▼
Apex HttpRequest → Named Credential (OpenWeatherMap)
        │           (API key never hardcoded in Apex)
        ▼
GET https://api.openweathermap.org/data/2.5/weather?q={city}&units=metric
        │
        ├─ 200 OK  → parse JSON → update Account.Weather_Info__c
        ├─ 404     → throw WeatherServiceException("City not found")
        └─ other   → throw WeatherServiceException with status code
```

---

## Sample Output on Account

`Account.Weather_Info__c` is updated to:
```
Paris, FR | 18.5°C | light rain | Humidity: 72% | Wind: 4.2 m/s
```

---

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── WeatherService.cls              # HTTP callout, JSON parsing, Account update
│   └── WeatherServiceTest.cls          # 4 test scenarios using HttpCalloutMock
└── namedCredentials/
    └── OpenWeatherMap.namedCredential-meta.xml
```

---

## Deployment

```bash
git clone https://github.com/YOUR_USERNAME/salesforce-api-integration.git
cd salesforce-api-integration
sf org login web --alias my-org

# 1. Create the custom field on Account first
#    Setup → Object Manager → Account → Fields → New → Text(255) → Label: Weather Info → API: Weather_Info__c

# 2. Deploy
sf project deploy start --target-org my-org

# 3. Add your OpenWeatherMap API key to the Named Credential
#    Setup → Named Credentials → OpenWeatherMap → Edit → add ?appid= to URL or use URL parameter

# 4. Run tests
sf apex run test --target-org my-org --test-level RunLocalTests --wait 10

# 5. Test in Anonymous Apex
WeatherService.fetchAndSaveWeather('YOUR_ACCOUNT_ID', 'Paris', 'YOUR_API_KEY');
```

---

## Test Coverage

| Test Method | Scenario |
|-------------|----------|
| `testSuccessfulWeatherFetch` | 200 response → all fields parsed correctly |
| `testCityNotFoundThrowsException` | 404 → typed exception with city name |
| `testApiErrorThrowsException` | 401 → typed exception with status code |
| `testFetchAndSaveUpdatesAccount` | End-to-end: API → Account field updated |

---

## Key Salesforce Concepts Demonstrated

- **Named Credentials** — API key kept out of code, managed in Setup
- **`HttpCalloutMock`** — proper unit testing of callouts without hitting the real API
- **`JSON.deserializeUntyped()`** — flexible JSON parsing for external API responses
- **Typed custom exceptions** (`WeatherServiceException`) — clean error surfacing
- **`EncodingUtil.urlEncode()`** — safe URL parameter construction
- **`Http().send()`** with timeout — defensive callout configuration

---

## Author

**Rida Najjari** — Salesforce Consultant, Developer & Administrator

4x Salesforce Certified: Platform Administrator · Platform App Builder · Platform Developer I · Associate

- LinkedIn: [linkedin.com/in/rida-najjari](https://www.linkedin.com/in/rida-najjari)
- GitHub: [github.com/ridanajjari](https://github.com/ridanajjari)
