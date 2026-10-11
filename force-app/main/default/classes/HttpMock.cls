/**
 * @description Configurable HttpCalloutMock for Apex tests. Describe each expected call with whenRequest(),
 * add its responses with thenRespond(), and register the mock with Test.setMock().
 *
 * How it behaves:
 * - A call matches a request when every criterion set on the request matches; unset criteria match anything.
 * - Text, including header names, is compared case-sensitively; only the HTTP method isn't.
 * - Requests are checked in the order they were added; the first match answers, even with no responses left.
 *   Add specific requests before broader ones; a broad request added first answers the calls meant for later ones.
 * - Each response is used once, in order; a response with an exception counts too. A call with no match
 *   or no responses left fails the test with an assert that the code under test can't catch.
 * - Setup mistakes, such as adding a request with the same criteria twice, throw HttpMockException.
 *   To add more responses to a request, call thenRespond() again before the next whenRequest().
 * - Requests and responses are copied when added, so later changes to them have no effect. Use deepClone()
 *   to build variants: the built-in clone() shares the headers map. Recorded calls are the code's own
 *   HttpRequest objects, not copies.
 *
 * @example
 * HttpMock.Request createPatient = HttpMock.request()
 *     .withMethod('POST')
 *     .withEndpoint('callout:ExampleApi/patients');
 *
 * // configure mocks
 * HttpMock.instance
 *     .whenRequest(createPatient)
 *     .thenRespond(new List<HttpMock.Response>{
 *         HttpMock.response().withException(new CalloutException('Read timed out')),
 *         HttpMock.response().withStatusCode(201)
 *     })
 *     .whenRequest(HttpMock.request()
 *         .withMethod('GET'))
 *     .thenRespond(HttpMock.response()
 *         .withJsonBody(new Map<String, Object>{ 'id' => 42 }));
 * // set the mock for the test context
 * Test.setMock(HttpCalloutMock.class, HttpMock.instance);
 *
 * // run the code under test
 *
 * HttpMock.instance.assertAllResponsesReturned();
 * HttpRequest retry = HttpMock.instance.getReceivedRequests(createPatient)[1];
 */
@IsTest
public class HttpMock implements HttpCalloutMock {

    public static HttpMock instance {
        get {
            if (instance == null) {
                instance = new HttpMock();
            }
            return instance;
        }
        private set;
    }

    private List<Expectation> expectations;
    private List<HttpRequest> receivedRequests;

    private HttpMock() {
        this.expectations = new List<Expectation>();
        this.receivedRequests = new List<HttpRequest>();
    }

    public static Request request() {
        return new Request();
    }

    public static Response response() {
        return new Response();
    }

    public HttpMock whenRequest(Request request) {
        if (request == null) {
            throw new HttpMockException('whenRequest() needs a request.');
        }

        if (this.findExpectation(request) != null) {
            throw new HttpMockException(
                'A request with the same criteria was already added with whenRequest().'
            );
        }

        this.expectations.add(new Expectation(request.deepClone()));
        return this;
    }

    public HttpMock thenRespond(Response response) {
        return this.thenRespond(new List<Response>{ response });
    }

    public HttpMock thenRespond(List<Response> responses) {
        if (this.expectations.isEmpty()) {
            throw new HttpMockException('Call whenRequest() before thenRespond().');
        }

        if (responses == null || responses.isEmpty()) {
            throw new HttpMockException('thenRespond() needs at least one response.');
        }

        if (responses.contains(null)) {
            throw new HttpMockException('thenRespond() responses must not be null.');
        }

        List<Response> responseCopies = new List<Response>();
        for (Response response : responses) {
            responseCopies.add(response.deepClone());
        }

        this.expectations[this.expectations.size() - 1].addResponses(responseCopies);
        return this;
    }

    public HttpResponse respond(HttpRequest httpRequest) {
        this.receivedRequests.add(httpRequest);
        return this.getNextResponse(httpRequest).build();
    }

    public List<HttpRequest> getReceivedRequests() {
        return new List<HttpRequest>(this.receivedRequests);
    }

    /**
     * @description Returns the calls matched to the request added with the same criteria, in call order,
     * including calls answered with an exception.
     * @param request Request with the same criteria as one added with whenRequest().
     * @return The matched calls; empty if the request was not called.
     * @throws HttpMockException if no request with the same criteria was added.
     */
    public List<HttpRequest> getReceivedRequests(Request request) {
        Expectation expectation = this.findExpectation(request);
        if (expectation == null) {
            throw new HttpMockException(
                'No request with the same criteria was added with whenRequest().'
            );
        }

        return expectation.getReceivedRequests();
    }

    /**
     * @description Fails the test if a response was never returned or a request has no responses.
     */
    public void assertAllResponsesReturned() {
        List<String> unreturnedResponses = new List<String>();
        for (Integer i = 0; i < this.expectations.size(); i++) {
            Expectation expectation = this.expectations[i];
            if (expectation.getResponseCount() == 0) {
                unreturnedResponses.add(String.format(
                    '#{0} {1}: no responses added with thenRespond()',
                    new List<Object>{ i + 1, expectation.describe() }
                ));
            } else if (expectation.getUnreturnedCount() > 0) {
                unreturnedResponses.add(String.format(
                    '#{0} {1}: {2} of {3} not returned',
                    new List<Object>{
                        i + 1,
                        expectation.describe(),
                        expectation.getUnreturnedCount(),
                        expectation.getResponseCount()
                    }
                ));
            }
        }

        Assert.isTrue(
            unreturnedResponses.isEmpty(),
            'Not all responses were returned: ' + String.join(unreturnedResponses, '; ') + '.'
        );
    }

    /**
     * @description Removes all requests and recorded calls. The instance stays registered with Test.setMock().
     * @return The same mock, for chaining.
     */
    public HttpMock reset() {
        this.expectations.clear();
        this.receivedRequests.clear();
        return this;
    }

    private Response getNextResponse(HttpRequest httpRequest) {
        Integer index = this.findMatchingIndex(httpRequest);
        Assert.isTrue(index != null, String.format(
            'Response is not found for {0} {1}.',
            new List<Object>{ httpRequest.getMethod(), httpRequest.getEndpoint() }
        ));

        Expectation expectation = this.expectations[index];
        Assert.isTrue(expectation.hasNextResponse(), String.format(
            'No responses left for {0} {1}: #{2} {3} returned all {4} responses.',
            new List<Object>{
                httpRequest.getMethod(),
                httpRequest.getEndpoint(),
                index + 1,
                expectation.describe(),
                expectation.getResponseCount()
            }
        ));

        return expectation.nextResponse(httpRequest);
    }

    private Integer findMatchingIndex(HttpRequest httpRequest) {
        for (Integer i = 0; i < this.expectations.size(); i++) {
            if (this.expectations[i].matches(httpRequest)) {
                return i;
            }
        }

        return null;
    }

    private Expectation findExpectation(Request request) {
        for (Expectation expectation : this.expectations) {
            if (expectation.hasSameCriteria(request)) {
                return expectation;
            }
        }

        return null;
    }

    private static String toJsonString(Object value) {
        return value instanceof String ? (String) value : JSON.serialize(value);
    }

    public class HttpMockException extends Exception {}

    /**
     * @description Custom criterion for Request.withMatcher().
     */
    public interface RequestMatcher {
        /**
         * @description Decides whether a call matches.
         * @param httpRequest The call made by the code under test.
         * @return True if the call matches.
         */
        Boolean matches(HttpRequest httpRequest);
    }

    public class Request {
        private String endpoint;
        private Pattern endpointPattern;
        private String method;
        private Map<String, String> headers;
        private String body;
        private String bodyFragment;
        private Object jsonBody;
        private RequestMatcher customMatcher;

        private Request() {
            this.headers = new Map<String, String>();
        }

        /**
         * @description Matches the exact endpoint, including the query string.
         * @param endpoint Endpoint as passed to setEndpoint(), such as 'callout:ExampleApi/patients?status=open'.
         * @return This request, for chaining.
         */
        public Request withEndpoint(String endpoint) {
            this.endpoint = endpoint;
            return this;
        }

        /**
         * @description Matches endpoints by a regular expression that must match the whole endpoint.
         * @param endpointPattern Regular expression, such as 'callout:ExampleApi/patients/[0-9]+'.
         * @return This request, for chaining.
         * @throws HttpMockException if the regular expression is invalid.
         */
        public Request withEndpointPattern(String endpointPattern) {
            try {
                this.endpointPattern = endpointPattern == null ? null : Pattern.compile(endpointPattern);
            } catch (StringException e) {
                throw new HttpMockException(
                    'withEndpointPattern() needs a valid regular expression.',
                    e
                );
            }

            return this;
        }

        public Request withMethod(String method) {
            this.method = method;
            return this;
        }

        public Request withHeader(String name, String value) {
            if (name == null || value == null) {
                throw new HttpMockException('withHeader() needs a non-null name and value.');
            }

            this.headers.put(name, value);
            return this;
        }

        public Request withBody(String body) {
            this.body = body;
            return this;
        }

        public Request withBodyContaining(String bodyFragment) {
            this.bodyFragment = bodyFragment;
            return this;
        }

        /**
         * @description Matches a body equal to this JSON, ignoring key order and whitespace;
         * array order and number format (1 vs 1.0) matter.
         * @param jsonBody JSON as a String, or any value to serialize.
         * @return This request, for chaining.
         * @throws HttpMockException if the JSON is invalid or null.
         */
        public Request withJsonBody(Object jsonBody) {
            Object expectedJson;
            try {
                expectedJson = JSON.deserializeUntyped(toJsonString(jsonBody));
            } catch (JSONException e) {
                throw new HttpMockException('withJsonBody() needs valid JSON.', e);
            }

            if (expectedJson == null) {
                throw new HttpMockException('JSON body must not be null.');
            }

            this.jsonBody = expectedJson;
            return this;
        }

        public Request withMatcher(RequestMatcher customMatcher) {
            this.customMatcher = customMatcher;
            return this;
        }

        public Request deepClone() {
            Request copy = (Request) this.clone();
            copy.headers = new Map<String, String>(this.headers);
            return copy;
        }

        private Boolean matches(HttpRequest httpRequest) {
            return this.matchesEndpoint(httpRequest.getEndpoint())
                && this.matchesMethod(httpRequest.getMethod())
                && this.matchesHeaders(httpRequest)
                && this.matchesBody(httpRequest.getBody())
                && this.matchesCustomMatcher(httpRequest);
        }

        private Boolean matchesEndpoint(String actualEndpoint) {
            if (this.endpoint != null && !this.equalsCaseSensitive(this.endpoint, actualEndpoint)) {
                return false;
            }

            return this.endpointPattern == null
                || (actualEndpoint != null && this.endpointPattern.matcher(actualEndpoint).matches());
        }

        private Boolean matchesMethod(String actualMethod) {
            return this.method == null || this.method.equalsIgnoreCase(actualMethod);
        }

        private Boolean matchesHeaders(HttpRequest httpRequest) {
            for (String name : this.headers.keySet()) {
                if (!this.equalsCaseSensitive(this.headers.get(name), httpRequest.getHeader(name))) {
                    return false;
                }
            }

            return true;
        }

        private Boolean matchesBody(String actualBody) {
            if (this.body != null && !this.equalsCaseSensitive(this.body, actualBody)) {
                return false;
            }

            if (this.bodyFragment != null && actualBody?.contains(this.bodyFragment) != true) {
                return false;
            }

            return this.jsonBody == null || this.matchesJsonBody(actualBody);
        }

        private Boolean matchesCustomMatcher(HttpRequest httpRequest) {
            return this.customMatcher == null || this.customMatcher.matches(httpRequest);
        }

        private Boolean matchesJsonBody(String actualBody) {
            try {
                return this.equalsJson(this.jsonBody, JSON.deserializeUntyped(actualBody));
            } catch (JSONException e) {
                return false;
            }
        }

        private Boolean hasSameCriteria(Request other) {
            return other != null
                && this.equalsCaseSensitive(this.endpoint, other.endpoint)
                && this.equalsCaseSensitive(this.endpointPattern?.pattern(), other.endpointPattern?.pattern())
                && this.hasSameMethod(other)
                && this.hasSameHeaders(other)
                && this.equalsCaseSensitive(this.body, other.body)
                && this.equalsCaseSensitive(this.bodyFragment, other.bodyFragment)
                && this.equalsJson(this.jsonBody, other.jsonBody)
                && this.customMatcher === other.customMatcher;
        }

        private Boolean hasSameMethod(Request other) {
            return this.method == null ? other.method == null : this.method.equalsIgnoreCase(other.method);
        }

        private Boolean hasSameHeaders(Request other) {
            if (this.headers.size() != other.headers.size()) {
                return false;
            }

            for (String name : this.headers.keySet()) {
                if (!this.equalsCaseSensitive(this.headers.get(name), other.headers.get(name))) {
                    return false;
                }
            }

            return true;
        }

        private Boolean equalsJson(Object left, Object right) {
            if (left instanceof String) {
                return right instanceof String && this.equalsCaseSensitive((String) left, (String) right);
            }

            return left == right;
        }

        private Boolean equalsCaseSensitive(String left, String right) {
            return left == null ? right == null : left.equals(right);
        }

        private String describe() {
            return String.format('{0} {1}', new List<Object>{
                this.method ?? 'any method',
                this.endpoint ?? this.endpointPattern?.pattern() ?? 'any endpoint'
            });
        }
    }

    public class Response {
        private String body;
        private Blob bodyAsBlob;
        private Integer statusCode;
        private String status;
        private Map<String, String> headers;
        private Exception exceptionToThrow;

        private Response() {
            this.statusCode = 200;
            this.headers = new Map<String, String>();
        }

        /**
         * @description Sets a text body; replaces a blob body.
         * @param body Response body.
         * @return This response, for chaining.
         */
        public Response withBody(String body) {
            this.body = body;
            this.bodyAsBlob = null;
            return this;
        }

        /**
         * @description Sets a binary body; replaces a text body.
         * @param bodyAsBlob Response body.
         * @return This response, for chaining.
         */
        public Response withBodyAsBlob(Blob bodyAsBlob) {
            this.bodyAsBlob = bodyAsBlob;
            this.body = null;
            return this;
        }

        /**
         * @description Sets a JSON body and Content-Type: application/json;
         * a later withHeader('Content-Type', ...) overrides the content type.
         * @param jsonBody JSON as a String, used as is, or any value to serialize.
         * @return This response, for chaining.
         */
        public Response withJsonBody(Object jsonBody) {
            this.withHeader('Content-Type', 'application/json');
            return this.withBody(toJsonString(jsonBody));
        }

        /**
         * @description Sets the status code; 200 when not set.
         * @param statusCode HTTP status code.
         * @return This response, for chaining.
         * @throws HttpMockException if the status code is null.
         */
        public Response withStatusCode(Integer statusCode) {
            if (statusCode == null) {
                throw new HttpMockException('withStatusCode() needs a non-null value.');
            }

            this.statusCode = statusCode;
            return this;
        }

        /**
         * @description Sets the status text.
         * @param status Status text, such as 'Not Found'.
         * @return This response, for chaining.
         */
        public Response withStatus(String status) {
            this.status = status;
            return this;
        }

        public Response withHeader(String name, String value) {
            if (name == null || value == null) {
                throw new HttpMockException('withHeader() needs a non-null name and value.');
            }

            this.headers.put(name, value);
            return this;
        }

        /**
         * @description Throws an exception to the code under test instead of returning a response.
         * @param exceptionToThrow Exception to throw, such as a CalloutException for a timeout.
         * @return This response, for chaining.
         */
        public Response withException(Exception exceptionToThrow) {
            this.exceptionToThrow = exceptionToThrow;
            return this;
        }

        public Response deepClone() {
            Response copy = (Response) this.clone();
            copy.headers = new Map<String, String>(this.headers);
            return copy;
        }

        private HttpResponse build() {
            if (this.exceptionToThrow != null) {
                throw this.exceptionToThrow;
            }

            HttpResponse httpResponse = new HttpResponse();
            httpResponse.setStatusCode(this.statusCode);

            if (this.status != null) {
                httpResponse.setStatus(this.status);
            }

            if (this.bodyAsBlob != null) {
                httpResponse.setBodyAsBlob(this.bodyAsBlob);
            } else if (this.body != null) {
                httpResponse.setBody(this.body);
            }

            for (String name : this.headers.keySet()) {
                httpResponse.setHeader(name, this.headers.get(name));
            }

            return httpResponse;
        }
    }

    private class Expectation {
        private Request request;
        private List<Response> responses;
        private List<HttpRequest> receivedRequests;

        private Expectation(Request request) {
            this.request = request;
            this.responses = new List<Response>();
            this.receivedRequests = new List<HttpRequest>();
        }

        private Boolean hasSameCriteria(Request request) {
            return this.request.hasSameCriteria(request);
        }

        private Boolean matches(HttpRequest httpRequest) {
            return this.request.matches(httpRequest);
        }

        private void addResponses(List<Response> responses) {
            this.responses.addAll(responses);
        }

        private Boolean hasNextResponse() {
            return this.receivedRequests.size() < this.responses.size();
        }

        private Response nextResponse(HttpRequest httpRequest) {
            Response response = this.responses[this.receivedRequests.size()];
            this.receivedRequests.add(httpRequest);
            return response;
        }

        private List<HttpRequest> getReceivedRequests() {
            return new List<HttpRequest>(this.receivedRequests);
        }

        private Integer getResponseCount() {
            return this.responses.size();
        }

        private Integer getUnreturnedCount() {
            return this.responses.size() - this.receivedRequests.size();
        }

        private String describe() {
            return this.request.describe();
        }
    }
}
