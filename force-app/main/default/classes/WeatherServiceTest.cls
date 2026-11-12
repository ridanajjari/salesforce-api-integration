@IsTest
private class WeatherServiceTest {
  private static final String RAW_BODY_MARKER = 'RAW_BODY_MARKER';

  private static void useTestKey() {
    WeatherService.apiKeyOverride = WeatherTestAccess.TEST_API_KEY;
  }

  @IsTest
  static void requestUsesNamedCredentialAndApiKey() {
    WeatherCalloutMock mock = new WeatherCalloutMock();
    useTestKey();
    Test.setMock(HttpCalloutMock.class, mock);

    WeatherService.callWeatherApi('San Francisco');

    Assert.areEqual(1, mock.requests.size(), 'Exactly one callout expected');
    HttpRequest req = mock.requests[0];
    Assert.areEqual('GET', req.getMethod(), 'Should be a GET');
    String endpoint = req.getEndpoint();
    Assert.isTrue(
      endpoint.startsWith('callout:OpenWeatherMap/data/2.5/weather?'),
      'Must go through the OpenWeatherMap Named Credential: ' + endpoint
    );
    Assert.isTrue(
      endpoint.contains('q=San+Francisco'),
      'City must be URL-encoded'
    );
    Assert.isTrue(endpoint.contains('units=metric'), 'Metric units expected');
    Assert.isTrue(
      endpoint.endsWith('&appid=' + WeatherTestAccess.TEST_API_KEY),
      'Key must be sent as the appid query parameter'
    );
  }

  @IsTest
  static void apiKeyIsReadFromCustomSetting() {
    WeatherTestAccess.configureApiKey('ORG_DEFAULT_KEY');
    WeatherCalloutMock mock = new WeatherCalloutMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    WeatherService.callWeatherApi('Paris');
    Test.stopTest();

    Assert.isTrue(
      mock.requests[0].getEndpoint().endsWith('&appid=ORG_DEFAULT_KEY'),
      'Key should come from OpenWeatherMap_Settings__c'
    );
  }

  @IsTest
  static void missingApiKeyThrowsWithoutCallout() {
    WeatherCalloutMock mock = new WeatherCalloutMock();
    Test.setMock(HttpCalloutMock.class, mock);

    try {
      WeatherService.callWeatherApi('Paris');
      Assert.fail('Expected WeatherServiceException was not thrown');
    } catch (WeatherService.WeatherServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('API key is not configured'),
        'Should explain the missing configuration'
      );
      Assert.areEqual(0, mock.requests.size(), 'No callout without a key');
    }
  }

  @IsTest
  static void successfulResponseIsParsed() {
    useTestKey();
    Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());

    WeatherService.WeatherResult result = WeatherService.callWeatherApi(
      'Paris'
    );

    Assert.areEqual('Paris', result.city, 'City should be Paris');
    Assert.areEqual('FR', result.country, 'Country should be FR');
    Assert.areEqual(
      18.5,
      result.tempCelsius,
      'Temperature should match mock data'
    );
    Assert.areEqual(
      'light rain',
      result.description,
      'Description should match mock data'
    );
    Assert.areEqual(72, result.humidity, 'Humidity should match mock data');
    Assert.areEqual(4.2, result.windSpeed, 'Wind speed should match mock data');
  }

  @IsTest
  static void optionalBlocksMayBeMissing() {
    useTestKey();
    Test.setMock(
      HttpCalloutMock.class,
      new WeatherCalloutMock(
        200,
        '{"name":"Oslo","main":{"temp":-3},"weather":[{"description":"snow"}]}'
      )
    );

    WeatherService.WeatherResult result = WeatherService.callWeatherApi('Oslo');

    Assert.isNull(result.country, 'Missing sys block should give null country');
    Assert.isNull(
      result.windSpeed,
      'Missing wind block should give null wind speed'
    );
    Assert.areEqual(
      'Oslo | -3°C | snow',
      WeatherService.formatSummary(result),
      'Summary skips missing parts'
    );
  }

  @IsTest
  static void cityNotFoundThrows() {
    useTestKey();
    Test.setMock(
      HttpCalloutMock.class,
      new WeatherCalloutMock(404, '{"message":"' + RAW_BODY_MARKER + '"}')
    );

    try {
      WeatherService.callWeatherApi('Atlantis');
      Assert.fail('Expected WeatherServiceException was not thrown');
    } catch (WeatherService.WeatherServiceException e) {
      Assert.areEqual(
        'City not found: Atlantis',
        e.getMessage(),
        'Message should name the city'
      );
    }
  }

  @IsTest
  static void non200StatusThrowsWithoutBody() {
    useTestKey();
    Test.setMock(
      HttpCalloutMock.class,
      new WeatherCalloutMock(401, '{"message":"' + RAW_BODY_MARKER + '"}')
    );

    try {
      WeatherService.callWeatherApi('Paris');
      Assert.fail('Expected WeatherServiceException was not thrown');
    } catch (WeatherService.WeatherServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('401'),
        'Exception should include the HTTP status code'
      );
      Assert.isFalse(
        e.getMessage().contains(RAW_BODY_MARKER),
        'Raw body must not leak into the message'
      );
    }
  }

  @IsTest
  static void calloutTimeoutIsWrapped() {
    WeatherCalloutMock mock = new WeatherCalloutMock();
    mock.throwTimeout = true;
    useTestKey();
    Test.setMock(HttpCalloutMock.class, mock);

    try {
      WeatherService.callWeatherApi('Paris');
      Assert.fail('Expected WeatherServiceException was not thrown');
    } catch (WeatherService.WeatherServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('callout failed'),
        'Should report a callout failure'
      );
      Assert.isInstanceOfType(
        e.getCause(),
        CalloutException.class,
        'Original CalloutException kept as cause'
      );
    }
  }

  @IsTest
  static void malformedBodyThrowsWithoutBody() {
    useTestKey();
    Test.setMock(
      HttpCalloutMock.class,
      new WeatherCalloutMock(200, '<html>' + RAW_BODY_MARKER)
    );

    try {
      WeatherService.callWeatherApi('Paris');
      Assert.fail('Expected WeatherServiceException was not thrown');
    } catch (WeatherService.WeatherServiceException e) {
      Assert.areEqual(
        'Weather API returned a malformed response',
        e.getMessage(),
        'Malformed JSON message'
      );
      Assert.isFalse(
        e.getMessage().contains(RAW_BODY_MARKER),
        'Raw body must not leak into the message'
      );
    }
  }

  @IsTest
  static void missingRequiredFieldsThrows() {
    useTestKey();
    Test.setMock(
      HttpCalloutMock.class,
      new WeatherCalloutMock(200, '{"name":"Paris","weather":[]}')
    );

    try {
      WeatherService.callWeatherApi('Paris');
      Assert.fail('Expected WeatherServiceException was not thrown');
    } catch (WeatherService.WeatherServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('missing required fields'),
        'Should flag missing fields'
      );
    }
  }

  @IsTest
  static void emptyBodyThrows() {
    useTestKey();
    Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock(200, ''));

    try {
      WeatherService.callWeatherApi('Paris');
      Assert.fail('Expected WeatherServiceException was not thrown');
    } catch (WeatherService.WeatherServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('empty response'),
        'Should flag empty body'
      );
    }
  }

  @IsTest
  static void blankCityThrowsWithoutCallout() {
    WeatherCalloutMock mock = new WeatherCalloutMock();
    useTestKey();
    Test.setMock(HttpCalloutMock.class, mock);

    try {
      WeatherService.callWeatherApi(' ');
      Assert.fail('Expected WeatherServiceException was not thrown');
    } catch (WeatherService.WeatherServiceException e) {
      Assert.areEqual(0, mock.requests.size(), 'No callout for a blank city');
    }
  }

  @IsTest
  static void fetchAndSaveUpdatesAccount() {
    User integrationUser = WeatherTestAccess.createIntegrationUser();
    System.runAs(integrationUser) {
      useTestKey();
      Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());

      Account acc = new Account(Name = 'Acme France');
      insert acc;

      Test.startTest();
      WeatherService.fetchAndSaveWeather(acc.Id, 'Paris');
      Test.stopTest();

      Account updated = [
        SELECT Weather_Info__c
        FROM Account
        WHERE Id = :acc.Id
      ];
      Assert.areEqual(
        'Paris, FR | 18.5°C | light rain | Humidity: 72% | Wind: 4.2 m/s',
        updated.Weather_Info__c,
        'Account should hold the formatted summary'
      );
    }
  }
}
