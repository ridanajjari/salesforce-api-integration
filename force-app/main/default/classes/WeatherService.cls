/**
 * Fetches current weather data from OpenWeatherMap and stores it
 * on the Account record as a custom text field (Weather_Info__c).
 *
 * API key handling:
 *   The key is stored in the OpenWeatherMap External Credential (named
 *   principal "OpenWeatherMapKey", authentication parameter "apiKey") and is
 *   entered in Setup, never in code or source control. OpenWeatherMap expects
 *   the key as the "appid" query parameter, so the request URL references it
 *   through the merge field {!$Credential.OpenWeatherMap.apiKey}; the platform
 *   substitutes the value when the callout is sent via the OpenWeatherMap
 *   Named Credential. Apex never sees the key.
 *
 * Integration pattern:
 *   1. Caller provides Account Id + city name
 *   2. Service calls OpenWeatherMap REST API via Named Credential
 *   3. Response is deserialized into a typed wrapper and validated
 *   4. Any callout, HTTP or parsing error is surfaced as WeatherServiceException.
 *      Exception messages never include the raw response body.
 */
public with sharing class WeatherService {
  @TestVisible
  private static final String ENDPOINT_BASE = 'callout:OpenWeatherMap/data/2.5/weather';

  // Resolved by the platform at callout time; the key itself is never in Apex.
  @TestVisible
  private static final String API_KEY_MERGE_FIELD = '{!$Credential.OpenWeatherMap.apiKey}';

  @TestVisible
  private static final Integer TIMEOUT_MS = 10000;

  private static final Integer FIELD_LENGTH = 255;

  public class WeatherServiceException extends Exception {
  }

  public class WeatherResult {
    public String city { get; set; }
    public String country { get; set; }
    public Decimal tempCelsius { get; set; }
    public String description { get; set; }
    public Integer humidity { get; set; }
    public Decimal windSpeed { get; set; }
  }

  // Typed shape of the parts of the OpenWeatherMap response we use.
  // Unknown JSON properties are ignored by JSON.deserialize. Public so the
  // JSON parser can instantiate them.
  public class OwmResponse {
    public String name;
    public OwmSys sys;
    public OwmMain main;
    public List<OwmWeather> weather;
    public OwmWind wind;
  }

  public class OwmSys {
    public String country;
  }

  public class OwmMain {
    public Decimal temp;
    public Integer humidity;
  }

  public class OwmWeather {
    public String description;
  }

  public class OwmWind {
    public Decimal speed;
  }

  /**
   * Fetches weather for a city and updates Account.Weather_Info__c (user mode).
   * Synchronous: one callout. For many accounts use WeatherSyncQueueable.
   * @param accountId  The Account to update
   * @param city       City name to query (e.g. "Paris")
   */
  public static WeatherResult fetchAndSaveWeather(Id accountId, String city) {
    WeatherResult result = callWeatherApi(city);
    Account acc = new Account(
      Id = accountId,
      Weather_Info__c = formatSummary(result)
    );
    update as user acc;
    return result;
  }

  public static WeatherResult callWeatherApi(String city) {
    if (String.isBlank(city)) {
      throw new WeatherServiceException('City is required');
    }

    HttpRequest req = new HttpRequest();
    req.setEndpoint(buildEndpoint(city));
    req.setMethod('GET');
    req.setTimeout(TIMEOUT_MS);

    HttpResponse res;
    try {
      res = new Http().send(req);
    } catch (CalloutException e) {
      // Timeouts and connection failures land here.
      throw new WeatherServiceException(
        'Weather API callout failed for city: ' + city,
        e
      );
    }

    Integer status = res.getStatusCode();
    if (status == 404) {
      throw new WeatherServiceException('City not found: ' + city);
    }
    if (status != 200) {
      throw new WeatherServiceException('Weather API returned HTTP ' + status);
    }

    return parseResponse(res.getBody());
  }

  /**
   * Builds the one-line summary stored on the Account, truncated to the field length.
   */
  public static String formatSummary(WeatherResult weather) {
    String info =
      weather.city +
      (String.isBlank(weather.country) ? '' : ', ' + weather.country) +
      ' | ' +
      weather.tempCelsius +
      '°C' +
      ' | ' +
      weather.description +
      (weather.humidity == null
        ? ''
        : ' | Humidity: ' + weather.humidity + '%') +
      (weather.windSpeed == null
        ? ''
        : ' | Wind: ' + weather.windSpeed + ' m/s');
    return info.left(FIELD_LENGTH);
  }

  @TestVisible
  private static String buildEndpoint(String city) {
    return ENDPOINT_BASE +
      '?q=' +
      EncodingUtil.urlEncode(city, 'UTF-8') +
      '&units=metric' +
      '&appid=' +
      API_KEY_MERGE_FIELD;
  }

  @TestVisible
  private static WeatherResult parseResponse(String body) {
    if (String.isBlank(body)) {
      throw new WeatherServiceException(
        'Weather API returned an empty response'
      );
    }

    OwmResponse parsed;
    try {
      parsed = (OwmResponse) JSON.deserialize(body, OwmResponse.class);
    } catch (JSONException e) {
      throw new WeatherServiceException(
        'Weather API returned a malformed response'
      );
    } catch (TypeException e) {
      throw new WeatherServiceException(
        'Weather API returned a malformed response'
      );
    }

    // Required: city name, temperature and at least one weather description.
    if (
      parsed == null ||
      String.isBlank(parsed.name) ||
      parsed.main == null ||
      parsed.main.temp == null ||
      parsed.weather == null ||
      parsed.weather.isEmpty() ||
      parsed.weather[0] == null ||
      String.isBlank(parsed.weather[0].description)
    ) {
      throw new WeatherServiceException(
        'Weather API response is missing required fields'
      );
    }

    WeatherResult result = new WeatherResult();
    result.city = parsed.name;
    result.country = parsed.sys == null ? null : parsed.sys.country;
    result.tempCelsius = parsed.main.temp;
    result.description = parsed.weather[0].description;
    result.humidity = parsed.main.humidity;
    result.windSpeed = parsed.wind == null ? null : parsed.wind.speed;
    return result;
  }
}
