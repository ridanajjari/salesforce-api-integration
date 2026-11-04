/**
 * Fetches current weather data from OpenWeatherMap and stores it
 * on the Account record as a custom text field (Weather_Info__c).
 *
 * Uses Named Credentials so the API key is never hardcoded in Apex.
 *
 * Integration pattern:
 *   1. Caller provides Account Id + city name
 *   2. Service calls OpenWeatherMap REST API via Named Credential
 *   3. Response is parsed and written back to Account.Weather_Info__c
 *   4. Any HTTP or API error is surfaced as a typed exception
 *
 * Setup:
 *   - Create Named Credential "OpenWeatherMap" pointing to https://api.openweathermap.org
 *   - Store your API key in a Custom Setting (WeatherApiConfig__c.Api_Key__c)
 *   - Add Account.Weather_Info__c (Text 255) custom field
 */
public with sharing class WeatherService {

    public class WeatherServiceException extends Exception {}

    public class WeatherResult {
        public String city        { get; set; }
        public String country     { get; set; }
        public Decimal tempCelsius{ get; set; }
        public String description { get; set; }
        public Integer humidity   { get; set; }
        public Decimal windSpeed  { get; set; }
    }

    /**
     * Fetches weather for a city and updates Account.Weather_Info__c.
     * @param accountId  The Account to update
     * @param city       City name to query (e.g. "Paris")
     * @param apiKey     OpenWeatherMap API key (passed in, never stored in code)
     */
    public static WeatherResult fetchAndSaveWeather(Id accountId, String city, String apiKey) {
        WeatherResult result = callWeatherApi(city, apiKey);
        updateAccount(accountId, result);
        return result;
    }

    public static WeatherResult callWeatherApi(String city, String apiKey) {
        String endpoint = 'callout:OpenWeatherMap/data/2.5/weather'
            + '?q='    + EncodingUtil.urlEncode(city, 'UTF-8')
            + '&appid=' + apiKey
            + '&units=metric';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(10000);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 404) {
            throw new WeatherServiceException('City not found: ' + city);
        }
        if (res.getStatusCode() != 200) {
            throw new WeatherServiceException(
                'Weather API error ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        return parseResponse(res.getBody());
    }

    private static WeatherResult parseResponse(String body) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);

        Map<String, Object> mainBlock = (Map<String, Object>) root.get('main');
        Map<String, Object> windBlock = (Map<String, Object>) root.get('wind');
        Map<String, Object> sysBlock  = (Map<String, Object>) root.get('sys');
        List<Object>        weatherList = (List<Object>) root.get('weather');
        Map<String, Object> weatherItem = (Map<String, Object>) weatherList[0];

        WeatherResult result  = new WeatherResult();
        result.city           = (String)  root.get('name');
        result.country        = (String)  sysBlock.get('country');
        result.tempCelsius    = Decimal.valueOf(String.valueOf(mainBlock.get('temp')));
        result.description    = (String)  weatherItem.get('description');
        result.humidity       = Integer.valueOf(String.valueOf(mainBlock.get('humidity')));
        result.windSpeed      = Decimal.valueOf(String.valueOf(windBlock.get('speed')));
        return result;
    }

    private static void updateAccount(Id accountId, WeatherResult weather) {
        String info = weather.city + ', ' + weather.country
            + ' | ' + weather.tempCelsius + '°C'
            + ' | ' + weather.description
            + ' | Humidity: ' + weather.humidity + '%'
            + ' | Wind: ' + weather.windSpeed + ' m/s';

        update new Account(Id = accountId, Weather_Info__c = info);
    }
}
