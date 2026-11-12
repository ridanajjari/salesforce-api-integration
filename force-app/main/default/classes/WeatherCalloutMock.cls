/**
 * Test-only HttpCalloutMock for OpenWeatherMap callouts.
 * - Records every request so tests can assert method and endpoint.
 * - Returns a configurable status/body, or throws CalloutException to
 *   simulate a timeout.
 * - Any request whose q= parameter is in notFoundCities gets a 404, so one
 *   mock can serve a mix of good and bad cities (partial-failure tests).
 */
@IsTest
public class WeatherCalloutMock implements HttpCalloutMock {
    public static final String SUCCESS_BODY =
        '{' +
        '"name":"Paris",' +
        '"sys":{"country":"FR"},' +
        '"main":{"temp":18.5,"humidity":72},' +
        '"weather":[{"description":"light rain"}],' +
        '"wind":{"speed":4.2}' +
        '}';

    public Integer statusCode = 200;
    public String body = SUCCESS_BODY;
    public Boolean throwTimeout = false;
    public Set<String> notFoundCities = new Set<String>();
    public List<HttpRequest> requests = new List<HttpRequest>();

    public WeatherCalloutMock() {
    }

    public WeatherCalloutMock(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body = body;
    }

    public HttpResponse respond(HttpRequest req) {
        requests.add(req);
        if (throwTimeout) {
            throw new CalloutException('Read timed out');
        }
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        for (String city : notFoundCities) {
            if (req.getEndpoint().contains('q=' + EncodingUtil.urlEncode(city, 'UTF-8') + '&')) {
                res.setStatusCode(404);
                res.setBody('{"cod":"404","message":"city not found"}');
                return res;
            }
        }
        res.setStatusCode(statusCode);
        res.setBody(body);
        return res;
    }
}
