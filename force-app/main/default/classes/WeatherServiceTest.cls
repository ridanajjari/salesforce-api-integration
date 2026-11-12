@IsTest
private class WeatherServiceTest {

    // Mock HTTP callout that returns a realistic OpenWeatherMap response
    private class WeatherMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  body;

        WeatherMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body       = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    private static final String MOCK_SUCCESS_BODY = '{'
        + '"name":"Paris",'
        + '"sys":{"country":"FR"},'
        + '"main":{"temp":18.5,"humidity":72},'
        + '"weather":[{"description":"light rain"}],'
        + '"wind":{"speed":4.2}'
        + '}';

    @IsTest
    static void testSuccessfulWeatherFetch() {
        Test.setMock(HttpCalloutMock.class, new WeatherMock(200, MOCK_SUCCESS_BODY));

        WeatherService.WeatherResult result = WeatherService.callWeatherApi('Paris');

        Assert.areEqual('Paris',      result.city,        'City should be Paris');
        Assert.areEqual('FR',         result.country,     'Country should be FR');
        Assert.areEqual(18.5,         result.tempCelsius, 'Temperature should match mock data');
        Assert.areEqual('light rain', result.description, 'Description should match mock data');
        Assert.areEqual(72,           result.humidity,    'Humidity should match mock data');
        Assert.areEqual(4.2,          result.windSpeed,   'Wind speed should match mock data');
    }

    @IsTest
    static void testCityNotFoundThrowsException() {
        Test.setMock(HttpCalloutMock.class, new WeatherMock(404, '{"message":"city not found"}'));

        try {
            WeatherService.callWeatherApi('Atlantis');
            Assert.fail('Expected WeatherServiceException was not thrown');
        } catch (WeatherService.WeatherServiceException e) {
            Assert.isTrue(e.getMessage().contains('City not found'), 'Exception message should mention the city');
        }
    }

    @IsTest
    static void testApiErrorThrowsException() {
        Test.setMock(HttpCalloutMock.class, new WeatherMock(401, '{"message":"Invalid API key"}'));

        try {
            WeatherService.callWeatherApi('Paris');
            Assert.fail('Expected WeatherServiceException was not thrown');
        } catch (WeatherService.WeatherServiceException e) {
            Assert.isTrue(e.getMessage().contains('401'), 'Exception should include the HTTP status code');
        }
    }

    @IsTest
    static void testFetchAndSaveUpdatesAccount() {
        Test.setMock(HttpCalloutMock.class, new WeatherMock(200, MOCK_SUCCESS_BODY));

        Account acc = new Account(Name = 'Acme France', Weather_Info__c = null);
        insert acc;

        Test.startTest();
        WeatherService.fetchAndSaveWeather(acc.Id, 'Paris');
        Test.stopTest();

        Account updated = [SELECT Weather_Info__c FROM Account WHERE Id = :acc.Id];
        Assert.isTrue(updated.Weather_Info__c.contains('Paris'),    'Weather info should contain city name');
        Assert.isTrue(updated.Weather_Info__c.contains('18.5'),     'Weather info should contain temperature');
        Assert.isTrue(updated.Weather_Info__c.contains('light rain'),'Weather info should contain description');
    }
}
