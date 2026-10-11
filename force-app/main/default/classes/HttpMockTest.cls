@IsTest
private class HttpMockTest {
    private static final String ENDPOINT = 'https://api.example.com/patients';
    private static final String OTHER_ENDPOINT = 'https://api.example.com/visits';
    private static final String MATCHED = 'matched';
    private static final String FALLBACK = 'fallback';

    private static final String WHEN_REQUEST_NULL = 'whenRequest() needs a request.';
    private static final String DUPLICATE_REQUEST =
        'A request with the same criteria was already added with whenRequest().';
    private static final String THEN_RESPOND_FIRST = 'Call whenRequest() before thenRespond().';
    private static final String NO_RESPONSES = 'thenRespond() needs at least one response.';
    private static final String NULL_RESPONSE = 'thenRespond() responses must not be null.';
    private static final String UNKNOWN_REQUEST = 'No request with the same criteria was added with whenRequest().';
    private static final String HEADER_REQUIRED = 'withHeader() needs a non-null name and value.';
    private static final String INVALID_PATTERN = 'withEndpointPattern() needs a valid regular expression.';
    private static final String INVALID_JSON = 'withJsonBody() needs valid JSON.';
    private static final String JSON_NULL = 'JSON body must not be null.';
    private static final String STATUS_CODE_REQUIRED = 'withStatusCode() needs a non-null value.';

    // Instance

    @IsTest
    static void instanceIsSingleton() {
        Assert.isTrue(
            HttpMock.instance === HttpMock.instance,
            'The instance should always be the same mock'
        );
    }

    @IsTest
    static void resetReturnsSameInstance() {
        HttpMock resetMock = HttpMock.instance.reset();

        Assert.isTrue(resetMock === HttpMock.instance, 'reset() should return the same instance');
    }

    @IsTest
    static void resetClearsReceivedRequests() {
        mock().whenRequest(HttpMock.request()).thenRespond(HttpMock.response());
        send(newCall('GET', ENDPOINT));
        Integer countBeforeReset = HttpMock.instance.getReceivedRequests().size();

        HttpMock.instance.reset();

        Assert.areEqual(1, countBeforeReset, 'The call should be recorded before reset()');
        Assert.isTrue(
            HttpMock.instance.getReceivedRequests().isEmpty(),
            'reset() should clear received requests'
        );
    }

    @IsTest
    static void resetRemovesRegisteredRequests() {
        HttpMock.Request anyRequest = HttpMock.request();
        mock().whenRequest(anyRequest).thenRespond(HttpMock.response().withBody('before reset'));

        HttpMock.instance
            .reset()
            .whenRequest(anyRequest)
            .thenRespond(HttpMock.response().withBody('after reset'));
        String body = send(newCall('GET', ENDPOINT)).getBody();

        Assert.areEqual('after reset', body, 'Only the request added after reset() should answer');
    }

    // Request matching

    @IsTest
    static void requestWithoutCriteriaMatchesAnyCall() {
        mock().whenRequest(HttpMock.request()).thenRespond(HttpMock.response().withBody(MATCHED));

        Boolean matched = isMatched(newCall('DELETE', OTHER_ENDPOINT));

        Assert.isTrue(matched, 'A request without criteria should match any call');
    }

    @IsTest
    static void endpointMatchesSameUrl() {
        mockWithFallback(HttpMock.request().withEndpoint(ENDPOINT));

        Assert.isTrue(isMatched(newCall('GET', ENDPOINT)), 'The same endpoint should match');
    }

    @IsTest
    static void endpointDoesNotMatchDifferentCase() {
        mockWithFallback(HttpMock.request().withEndpoint(ENDPOINT));

        Assert.isFalse(isMatched(newCall('GET', ENDPOINT.toUpperCase())), 'The endpoint should be case-sensitive');
    }

    @IsTest
    static void endpointDoesNotMatchDifferentQueryString() {
        mockWithFallback(HttpMock.request().withEndpoint(ENDPOINT + '?status=open'));

        Assert.isFalse(
            isMatched(newCall('GET', ENDPOINT + '?status=closed')),
            'The query string should be part of the endpoint'
        );
    }

    @IsTest
    static void endpointPatternMatchesWholeUrl() {
        mockWithFallback(HttpMock.request().withEndpointPattern('.*/patients/[0-9]+'));

        Assert.isTrue(isMatched(newCall('GET', ENDPOINT + '/42')), 'The pattern should match the whole URL');
    }

    @IsTest
    static void endpointPatternDoesNotMatchPartOfUrl() {
        mockWithFallback(HttpMock.request().withEndpointPattern('.*/patients/[0-9]+'));

        Assert.isFalse(
            isMatched(newCall('GET', ENDPOINT + '/42/visits')),
            'The pattern should not match only part of the URL'
        );
    }

    @IsTest
    static void endpointWithPatternDoesNotMatchWhenPatternFails() {
        mockWithFallback(HttpMock.request().withEndpoint(ENDPOINT).withEndpointPattern('.*/visits'));

        Assert.isFalse(isMatched(newCall('GET', ENDPOINT)), 'The endpoint and the pattern should both have to match');
    }

    @IsTest
    static void endpointPatternSetToNullRemovesEarlierPattern() {
        // The method keeps this request different from the fallback, which has no criteria.
        mockWithFallback(HttpMock.request()
            .withMethod('GET')
            .withEndpointPattern('.*/visits')
            .withEndpointPattern(null));

        Assert.isTrue(isMatched(newCall('GET', ENDPOINT)), 'A null pattern should remove the earlier pattern');
    }

    @IsTest
    static void methodMatchesInAnyCase() {
        mockWithFallback(HttpMock.request().withMethod('post'));

        Assert.isTrue(isMatched(newCall('POST', ENDPOINT)), 'The method should be case-insensitive');
    }

    @IsTest
    static void methodDoesNotMatchOtherMethod() {
        mockWithFallback(HttpMock.request().withMethod('POST'));

        Assert.isFalse(isMatched(newCall('GET', ENDPOINT)), 'A different method should not match');
    }

    @IsTest
    static void headerMatchesSameValue() {
        mockWithFallback(HttpMock.request().withHeader('Authorization', 'Bearer abc'));
        HttpRequest call = newCall('GET', ENDPOINT);
        call.setHeader('Authorization', 'Bearer abc');

        Assert.isTrue(isMatched(call), 'The same header value should match');
    }

    @IsTest
    static void headerDoesNotMatchValueInDifferentCase() {
        mockWithFallback(HttpMock.request().withHeader('Authorization', 'Bearer abc'));
        HttpRequest call = newCall('GET', ENDPOINT);
        call.setHeader('Authorization', 'Bearer ABC');

        Assert.isFalse(isMatched(call), 'The header value should be case-sensitive');
    }

    @IsTest
    static void headerDoesNotMatchNameInDifferentCase() {
        mockWithFallback(HttpMock.request().withHeader('Content-Type', 'application/json'));
        HttpRequest call = newCall('GET', ENDPOINT);
        call.setHeader('content-type', 'application/json');

        Assert.isFalse(isMatched(call), 'The header name should be case-sensitive, like HttpRequest.getHeader()');
    }

    @IsTest
    static void headerDoesNotMatchMissingHeader() {
        mockWithFallback(HttpMock.request().withHeader('Authorization', 'Bearer abc'));

        Assert.isFalse(isMatched(newCall('GET', ENDPOINT)), 'A missing header should not match');
    }

    @IsTest
    static void headerMatchesWhenCallHasOtherHeaders() {
        mockWithFallback(HttpMock.request().withHeader('Authorization', 'Bearer abc'));
        HttpRequest call = newCall('GET', ENDPOINT);
        call.setHeader('Authorization', 'Bearer abc');
        call.setHeader('Accept', 'application/json');

        Assert.isTrue(isMatched(call), 'Headers the request does not name should be ignored');
    }

    @IsTest
    static void headersMatchOnlyWhenEveryHeaderMatches() {
        mockWithFallback(HttpMock.request()
            .withHeader('Authorization', 'Bearer abc')
            .withHeader('Accept', 'application/json'));
        HttpRequest bothHeadersRight = newCall('GET', ENDPOINT);
        bothHeadersRight.setHeader('Authorization', 'Bearer abc');
        bothHeadersRight.setHeader('Accept', 'application/json');
        HttpRequest firstHeaderWrong = newCall('GET', ENDPOINT);
        firstHeaderWrong.setHeader('Authorization', 'Bearer xyz');
        firstHeaderWrong.setHeader('Accept', 'application/json');
        HttpRequest secondHeaderWrong = newCall('GET', ENDPOINT);
        secondHeaderWrong.setHeader('Authorization', 'Bearer abc');
        secondHeaderWrong.setHeader('Accept', 'text/plain');

        Boolean bothRightMatched = isMatched(bothHeadersRight);
        Boolean firstWrongMatched = isMatched(firstHeaderWrong);
        Boolean secondWrongMatched = isMatched(secondHeaderWrong);

        Assert.isTrue(bothRightMatched, 'All headers right should match');
        Assert.isFalse(firstWrongMatched, 'A wrong Authorization header should not match');
        Assert.isFalse(secondWrongMatched, 'A wrong Accept header should not match');
    }

    @IsTest
    static void emptyHeaderMatchesHeaderSetToEmpty() {
        mockWithFallback(HttpMock.request().withHeader('X-Trace', ''));
        HttpRequest call = newCall('GET', ENDPOINT);
        call.setHeader('X-Trace', '');

        Assert.isTrue(isMatched(call), 'An empty header value should match a header set to empty');
    }

    @IsTest
    static void emptyHeaderDoesNotMatchMissingHeader() {
        mockWithFallback(HttpMock.request().withHeader('X-Trace', ''));

        Assert.isFalse(isMatched(newCall('GET', ENDPOINT)), 'An empty header value should not match a missing header');
    }

    @IsTest
    static void bodyMatchesSameText() {
        mockWithFallback(HttpMock.request().withBody('name=John'));

        Assert.isTrue(isMatched(newCall('POST', ENDPOINT, 'name=John')), 'The same body should match');
    }

    @IsTest
    static void bodyDoesNotMatchDifferentCase() {
        mockWithFallback(HttpMock.request().withBody('name=John'));

        Assert.isFalse(isMatched(newCall('POST', ENDPOINT, 'name=JOHN')), 'The body should be case-sensitive');
    }

    @IsTest
    static void bodyContainingMatchesFragment() {
        mockWithFallback(HttpMock.request().withBodyContaining('John'));

        Assert.isTrue(
            isMatched(newCall('POST', ENDPOINT, 'name=John&age=33')),
            'A body containing the fragment should match'
        );
    }

    @IsTest
    static void bodyContainingDoesNotMatchFragmentInDifferentCase() {
        mockWithFallback(HttpMock.request().withBodyContaining('John'));

        Assert.isFalse(
            isMatched(newCall('POST', ENDPOINT, 'name=JOHN&age=33')),
            'The body fragment should be case-sensitive'
        );
    }

    @IsTest
    static void bodyContainingDoesNotMatchMissingBody() {
        mockWithFallback(HttpMock.request().withBodyContaining('John'));

        Assert.isFalse(isMatched(newCall('GET', ENDPOINT)), 'A call without a body should not match a fragment');
    }

    @IsTest
    static void jsonBodyMatchesRegardlessOfKeyOrderAndWhitespace() {
        mockWithFallback(HttpMock.request().withJsonBody(new Map<String, Object>{
            'name' => 'John',
            'tags' => new List<Object>{ 'a', 'b' }
        }));

        Assert.isTrue(
            isMatched(newCall('POST', ENDPOINT, '{ "tags": ["a", "b"], "name": "John" }')),
            'JSON should be compared by structure'
        );
    }

    @IsTest
    static void jsonBodyDoesNotMatchValueInDifferentCase() {
        mockWithFallback(HttpMock.request().withJsonBody(new Map<String, Object>{ 'name' => 'John' }));

        Assert.isFalse(isMatched(newCall('POST', ENDPOINT, '{"name":"JOHN"}')), 'JSON values should be case-sensitive');
    }

    @IsTest
    static void jsonBodyDoesNotMatchArrayInDifferentOrder() {
        mockWithFallback(HttpMock.request().withJsonBody('{"tags": ["a", "b"]}'));

        Assert.isFalse(isMatched(newCall('POST', ENDPOINT, '{"tags": ["b", "a"]}')), 'JSON array order should matter');
    }

    @IsTest
    static void jsonBodyFromStringMatchesRegardlessOfWhitespace() {
        mockWithFallback(HttpMock.request().withJsonBody('{ "id": 1 }'));

        Assert.isTrue(isMatched(newCall('POST', ENDPOINT, '{"id":1}')), 'A String argument should be parsed as JSON');
    }

    @IsTest
    static void jsonBodyMatchesTopLevelString() {
        mockWithFallback(HttpMock.request().withJsonBody('"abc"'));

        Assert.isTrue(isMatched(newCall('POST', ENDPOINT, '"abc"')), 'The same top-level JSON string should match');
    }

    @IsTest
    static void jsonBodyDoesNotMatchTopLevelStringInDifferentCase() {
        mockWithFallback(HttpMock.request().withJsonBody('"abc"'));

        Assert.isFalse(
            isMatched(newCall('POST', ENDPOINT, '"ABC"')),
            'A top-level JSON string should be case-sensitive'
        );
    }

    // Records current behavior: JSON.deserializeUntyped turns 1 into an Integer and 1.0 into a Decimal.
    @IsTest
    static void jsonBodyDoesNotMatchIntegerWrittenAsDecimal() {
        mockWithFallback(HttpMock.request().withJsonBody('{"amount": 1}'));

        Assert.isFalse(
            isMatched(newCall('POST', ENDPOINT, '{"amount": 1.0}')),
            '1 and 1.0 should be different JSON values'
        );
    }

    @IsTest
    static void jsonBodyDoesNotMatchInvalidJson() {
        mockWithFallback(HttpMock.request().withJsonBody('{"id": 1}'));

        Assert.isFalse(isMatched(newCall('POST', ENDPOINT, 'not json')), 'An invalid JSON body should not match');
    }

    @IsTest
    static void jsonBodyDoesNotMatchMissingBody() {
        mockWithFallback(HttpMock.request().withJsonBody('{"id": 1}'));

        Assert.isFalse(isMatched(newCall('GET', ENDPOINT)), 'A call without a body should not match JSON');
    }

    @IsTest
    static void jsonBodyDoesNotMatchWhenOnlyFragmentMatches() {
        mockWithFallback(HttpMock.request().withBodyContaining('John').withJsonBody('{"name": "John"}'));

        Assert.isFalse(
            isMatched(newCall('POST', ENDPOINT, '{"name": "John", "age": 33}')),
            'Every body criterion should have to match'
        );
    }

    @IsTest
    static void customMatcherMatchesWhenItAccepts() {
        mockWithFallback(HttpMock.request().withMatcher(new CompressedRequestMatcher()));
        HttpRequest call = newCall('GET', ENDPOINT);
        call.setCompressed(true);

        Assert.isTrue(isMatched(call), 'The custom matcher should accept a compressed call');
    }

    @IsTest
    static void customMatcherDoesNotMatchWhenItRejects() {
        mockWithFallback(HttpMock.request().withMatcher(new CompressedRequestMatcher()));

        Assert.isFalse(isMatched(newCall('GET', ENDPOINT)), 'The custom matcher should reject an uncompressed call');
    }

    @IsTest
    static void customMatcherDoesNotMatchWhenOtherCriteriaFail() {
        mockWithFallback(HttpMock.request().withEndpoint(ENDPOINT).withMatcher(new CompressedRequestMatcher()));
        HttpRequest call = newCall('GET', OTHER_ENDPOINT);
        call.setCompressed(true);

        Assert.isFalse(isMatched(call), 'The custom matcher should not replace the other criteria');
    }

    @IsTest
    static void requestDoesNotMatchWhenOnlySomeCriteriaMatch() {
        mockWithFallback(HttpMock.request().withEndpoint(ENDPOINT).withMethod('POST'));

        Boolean wrongMethodMatched = isMatched(newCall('GET', ENDPOINT));
        Boolean wrongEndpointMatched = isMatched(newCall('POST', OTHER_ENDPOINT));
        Boolean allCriteriaMatched = isMatched(newCall('POST', ENDPOINT));

        Assert.isFalse(wrongMethodMatched, 'The right endpoint with the wrong method should not match');
        Assert.isFalse(wrongEndpointMatched, 'The right method with the wrong endpoint should not match');
        Assert.isTrue(allCriteriaMatched, 'The right endpoint and method should match');
    }

    @IsTest
    static void firstRegisteredMatchingRequestAnswers() {
        mock()
            .whenRequest(HttpMock.request().withMethod('GET'))
            .thenRespond(HttpMock.response().withBody('first'))
            .whenRequest(HttpMock.request().withMethod('GET').withEndpoint(ENDPOINT))
            .thenRespond(HttpMock.response().withBody('second'));

        String body = send(newCall('GET', ENDPOINT)).getBody();

        Assert.areEqual('first', body, 'The first registered matching request should answer');
    }

    // Responses

    @IsTest
    static void defaultResponseHasStatus200AndNoBody() {
        HttpResponse httpResponse = callReturning(HttpMock.response());

        Assert.areEqual(200, httpResponse.getStatusCode(), 'The status code should default to 200');
        Assert.isTrue(String.isBlank(httpResponse.getBody()), 'The body should be empty by default');
    }

    @IsTest
    static void responseHasStatusCodeAndStatus() {
        HttpResponse httpResponse = callReturning(HttpMock.response()
            .withStatusCode(404)
            .withStatus('Not Found'));

        Assert.areEqual(404, httpResponse.getStatusCode(), 'The status code should be set');
        Assert.areEqual('Not Found', httpResponse.getStatus(), 'The status should be set');
    }

    @IsTest
    static void responseHasHeaders() {
        HttpResponse httpResponse = callReturning(HttpMock.response()
            .withHeader('Location', ENDPOINT + '/42')
            .withHeader('X-Request-Id', 'abc'));

        Assert.areEqual(ENDPOINT + '/42', httpResponse.getHeader('Location'), 'The Location header should be set');
        Assert.areEqual('abc', httpResponse.getHeader('X-Request-Id'), 'The custom header should be set');
    }

    @IsTest
    static void responseHasTextBody() {
        HttpResponse httpResponse = callReturning(HttpMock.response().withBody('ok'));

        Assert.areEqual('ok', httpResponse.getBody(), 'The text body should be set');
    }

    @IsTest
    static void responseHasBlobBody() {
        HttpResponse httpResponse = callReturning(HttpMock.response().withBodyAsBlob(Blob.valueOf('%PDF')));

        Assert.areEqual('%PDF', httpResponse.getBodyAsBlob().toString(), 'The blob body should be set');
    }

    @IsTest
    static void responseTextBodyReplacesBlobBody() {
        HttpResponse httpResponse = callReturning(HttpMock.response()
            .withBodyAsBlob(Blob.valueOf('blob'))
            .withBody('text'));

        Assert.areEqual('text', httpResponse.getBody(), 'withBody() should replace an earlier blob body');
    }

    @IsTest
    static void responseNullBlobBodyClearsTextBody() {
        HttpResponse httpResponse = callReturning(HttpMock.response()
            .withBody('text')
            .withBodyAsBlob(null));

        Assert.isTrue(String.isBlank(httpResponse.getBody()), 'withBodyAsBlob() should clear an earlier text body');
    }

    @IsTest
    static void responseJsonBodyIsSerializedWithContentType() {
        HttpResponse httpResponse = callReturning(HttpMock.response()
            .withJsonBody(new Map<String, Object>{ 'id' => 42 }));

        Assert.areEqual('{"id":42}', httpResponse.getBody(), 'The object should be serialized to JSON');
        Assert.areEqual('application/json', httpResponse.getHeader('Content-Type'), 'Content-Type should be JSON');
    }

    @IsTest
    static void responseJsonBodyFromStringIsUsedAsIs() {
        HttpResponse httpResponse = callReturning(HttpMock.response().withJsonBody('{ "id": 42 }'));

        Assert.areEqual('{ "id": 42 }', httpResponse.getBody(), 'A String argument should be used as raw JSON');
    }

    @IsTest
    static void responseJsonBodyFromNullIsJsonNull() {
        HttpResponse httpResponse = callReturning(HttpMock.response().withJsonBody(null));

        Assert.areEqual('null', httpResponse.getBody(), 'A null argument should be serialized as JSON null');
    }

    @IsTest
    static void responseHeaderOverridesJsonContentType() {
        HttpResponse httpResponse = callReturning(HttpMock.response()
            .withJsonBody(new Map<String, Object>{ 'error' => 'Not found' })
            .withHeader('Content-Type', 'application/problem+json'));

        Assert.areEqual(
            'application/problem+json',
            httpResponse.getHeader('Content-Type'),
            'A later Content-Type header should replace the JSON default'
        );
    }

    @IsTest
    static void responseThrowsConfiguredException() {
        CalloutException configuredError = new CalloutException('Read timed out');
        CalloutException error;

        try {
            callReturning(HttpMock.response().withException(configuredError));
        } catch (CalloutException e) {
            error = e;
        }

        Assert.isTrue(error === configuredError, 'The configured exception should reach the caller');
    }

    // Response sequences

    @IsTest
    static void responsesAreReturnedInOrder() {
        mock()
            .whenRequest(HttpMock.request())
            .thenRespond(new List<HttpMock.Response>{
                HttpMock.response().withStatusCode(503),
                HttpMock.response().withStatusCode(429),
                HttpMock.response().withStatusCode(201)
            });

        List<Integer> statusCodes = new List<Integer>{
            send(newCall('POST', ENDPOINT)).getStatusCode(),
            send(newCall('POST', ENDPOINT)).getStatusCode(),
            send(newCall('POST', ENDPOINT)).getStatusCode()
        };

        Assert.areEqual(new List<Integer>{ 503, 429, 201 }, statusCodes, 'Responses should be returned in order');
    }

    @IsTest
    static void thenRespondAgainAppendsResponses() {
        mock()
            .whenRequest(HttpMock.request())
            .thenRespond(HttpMock.response().withBody('first'))
            .thenRespond(HttpMock.response().withBody('second'));

        String firstBody = send(newCall('GET', ENDPOINT)).getBody();
        String secondBody = send(newCall('GET', ENDPOINT)).getBody();

        Assert.areEqual('first', firstBody, 'The first response should be returned first');
        Assert.areEqual('second', secondBody, 'The appended response should be returned second');
    }

    @IsTest
    static void eachRequestHasItsOwnResponses() {
        mock()
            .whenRequest(HttpMock.request().withMethod('GET'))
            .thenRespond(new List<HttpMock.Response>{
                HttpMock.response().withBody('get 1'),
                HttpMock.response().withBody('get 2')
            })
            .whenRequest(HttpMock.request().withMethod('POST'))
            .thenRespond(HttpMock.response().withBody('post 1'));

        String firstGet = send(newCall('GET', ENDPOINT)).getBody();
        String firstPost = send(newCall('POST', ENDPOINT)).getBody();
        String secondGet = send(newCall('GET', ENDPOINT)).getBody();

        Assert.areEqual('get 1', firstGet, 'The first GET should get the first GET response');
        Assert.areEqual('post 1', firstPost, 'The POST should get its own response');
        Assert.areEqual('get 2', secondGet, 'The second GET should get the second GET response');
    }

    @IsTest
    static void sameResponseInstanceCanBeReturnedTwice() {
        HttpMock.Response ok = HttpMock.response().withBody('ok');
        mock()
            .whenRequest(HttpMock.request())
            .thenRespond(new List<HttpMock.Response>{ ok, ok });

        String firstBody = send(newCall('GET', ENDPOINT)).getBody();
        String secondBody = send(newCall('GET', ENDPOINT)).getBody();

        Assert.areEqual('ok', firstBody, 'The first call should get the response');
        Assert.areEqual('ok', secondBody, 'The second call should get the same response again');
        HttpMock.instance.assertAllResponsesReturned();
    }

    @IsTest
    static void exceptionResponseIsUsedUpAndRecorded() {
        HttpMock.Request createPatient = HttpMock.request().withMethod('POST');
        CalloutException timeout = new CalloutException('Read timed out');
        mock()
            .whenRequest(createPatient)
            .thenRespond(new List<HttpMock.Response>{
                HttpMock.response().withException(timeout),
                HttpMock.response().withStatusCode(201)
            });
        CalloutException firstError;

        try {
            send(newCall('POST', ENDPOINT));
        } catch (CalloutException e) {
            firstError = e;
        }
        Integer retryStatusCode = send(newCall('POST', ENDPOINT)).getStatusCode();

        Assert.isTrue(firstError === timeout, 'The first call should throw the configured exception');
        Assert.areEqual(201, retryStatusCode, 'The retry should get the next response');
        Assert.areEqual(
            2,
            HttpMock.instance.getReceivedRequests(createPatient).size(),
            'Both calls should be recorded'
        );
        HttpMock.instance.assertAllResponsesReturned();
    }

    // Received requests

    @IsTest
    static void allReceivedRequestsAreRecordedInCallOrder() {
        mock()
            .whenRequest(HttpMock.request())
            .thenRespond(new List<HttpMock.Response>{
                HttpMock.response(),
                HttpMock.response()
            });
        HttpRequest firstCall = newCall('GET', ENDPOINT);
        HttpRequest secondCall = newCall('POST', ENDPOINT);

        send(firstCall);
        send(secondCall);
        List<HttpRequest> receivedRequests = HttpMock.instance.getReceivedRequests();

        Assert.areEqual(2, receivedRequests.size(), 'Both calls should be recorded');
        Assert.isTrue(receivedRequests[0] === firstCall, 'The first call should be recorded first');
        Assert.isTrue(receivedRequests[1] === secondCall, 'The second call should be recorded second');
    }

    @IsTest
    static void receivedRequestsAreRecordedPerRequest() {
        HttpMock.Request createPatient = HttpMock.request().withMethod('POST');
        HttpMock.Request readPatient = HttpMock.request().withMethod('GET');
        mock()
            .whenRequest(createPatient)
            .thenRespond(new List<HttpMock.Response>{
                HttpMock.response(),
                HttpMock.response()
            })
            .whenRequest(readPatient)
            .thenRespond(HttpMock.response());

        send(newCall('POST', ENDPOINT, 'attempt 1'));
        send(newCall('GET', ENDPOINT));
        send(newCall('POST', ENDPOINT, 'attempt 2'));
        List<HttpRequest> createCalls = HttpMock.instance.getReceivedRequests(createPatient);

        Assert.areEqual(2, createCalls.size(), 'Only the POST calls should be listed');
        Assert.areEqual('attempt 1', createCalls[0].getBody(), 'The first attempt should be listed first');
        Assert.areEqual('attempt 2', createCalls[1].getBody(), 'The retry should be listed second');
    }

    @IsTest
    static void receivedRequestsAreFoundByCriteriaNotInstance() {
        mock()
            .whenRequest(HttpMock.request().withMethod('POST').withEndpoint(ENDPOINT))
            .thenRespond(HttpMock.response());
        send(newCall('POST', ENDPOINT));

        HttpMock.Request equalRequest = HttpMock.request().withMethod('post').withEndpoint(ENDPOINT);
        List<HttpRequest> receivedRequests = HttpMock.instance.getReceivedRequests(equalRequest);

        Assert.areEqual(1, receivedRequests.size(), 'A request with the same criteria should find the recorded call');
    }

    @IsTest
    static void receivedRequestsAreEmptyWhenRequestWasNotCalled() {
        HttpMock.Request deletePatient = HttpMock.request().withMethod('DELETE');
        mock().whenRequest(deletePatient).thenRespond(HttpMock.response());

        List<HttpRequest> receivedRequests = HttpMock.instance.getReceivedRequests(deletePatient);

        Assert.isTrue(receivedRequests.isEmpty(), 'A request that was not called should have no recorded calls');
    }

    @IsTest
    static void getReceivedRequestsReturnsCopies() {
        HttpMock.Request anyRequest = HttpMock.request();
        mock().whenRequest(anyRequest).thenRespond(HttpMock.response());
        send(newCall('GET', ENDPOINT));

        HttpMock.instance.getReceivedRequests().clear();
        HttpMock.instance.getReceivedRequests(anyRequest).clear();

        Assert.areEqual(1, HttpMock.instance.getReceivedRequests().size(), 'All recorded calls should be kept');
        Assert.areEqual(
            1,
            HttpMock.instance.getReceivedRequests(anyRequest).size(),
            'The recorded calls of the request should be kept'
        );
    }

    // Copies

    @IsTest
    static void changingRequestAfterRegistrationHasNoEffect() {
        HttpMock.Request request = HttpMock.request().withMethod('GET').withHeader('X-Id', '1');
        mockWithFallback(request);
        HttpRequest originalCall = newCall('GET', ENDPOINT);
        originalCall.setHeader('X-Id', '1');
        HttpRequest changedCall = newCall('POST', ENDPOINT);
        changedCall.setHeader('X-Id', '2');

        request.withMethod('POST').withHeader('X-Id', '2');

        Assert.isTrue(isMatched(originalCall), 'The registered request should keep its original criteria');
        Assert.isFalse(isMatched(changedCall), 'The later changes should not reach the registered request');
    }

    @IsTest
    static void changingResponseAfterRegistrationHasNoEffect() {
        HttpMock.Response response = HttpMock.response()
            .withBody('original')
            .withHeader('X-Version', '1');
        mock().whenRequest(HttpMock.request()).thenRespond(response);

        response.withBody('changed').withHeader('X-Version', '2');
        HttpResponse httpResponse = send(newCall('GET', ENDPOINT));

        Assert.areEqual('original', httpResponse.getBody(), 'The registered response should keep its body');
        Assert.areEqual('1', httpResponse.getHeader('X-Version'), 'The registered response should keep its headers');
    }

    @IsTest
    static void requestDeepCloneKeepsCriteriaAndIsIndependent() {
        HttpMock.Request base = HttpMock.request().withEndpoint(ENDPOINT).withHeader('X-Id', '1');
        HttpMock.Request variant = base.deepClone().withHeader('X-Id', '2');
        mock()
            .whenRequest(base)
            .thenRespond(HttpMock.response().withBody('base'))
            .whenRequest(variant)
            .thenRespond(HttpMock.response().withBody('variant'))
            .whenRequest(HttpMock.request())
            .thenRespond(HttpMock.response().withBody(FALLBACK));
        HttpRequest baseCall = newCall('GET', ENDPOINT);
        baseCall.setHeader('X-Id', '1');
        HttpRequest variantCall = newCall('GET', ENDPOINT);
        variantCall.setHeader('X-Id', '2');
        HttpRequest otherEndpointCall = newCall('GET', OTHER_ENDPOINT);
        otherEndpointCall.setHeader('X-Id', '2');

        String baseBody = send(baseCall).getBody();
        String variantBody = send(variantCall).getBody();
        String otherEndpointBody = send(otherEndpointCall).getBody();

        Assert.areEqual('base', baseBody, 'Changing the clone should not change the original');
        Assert.areEqual('variant', variantBody, 'The clone should have its own header');
        Assert.areEqual(FALLBACK, otherEndpointBody, 'The clone should keep the original endpoint');
    }

    @IsTest
    static void responseDeepCloneKeepsContentAndIsIndependent() {
        HttpMock.Response base = HttpMock.response()
            .withBody('shared body')
            .withHeader('X-Version', '1');
        HttpMock.Response variant = base.deepClone().withHeader('X-Version', '2');
        mock()
            .whenRequest(HttpMock.request())
            .thenRespond(new List<HttpMock.Response>{ base, variant });

        HttpResponse baseResponse = send(newCall('GET', ENDPOINT));
        HttpResponse variantResponse = send(newCall('GET', ENDPOINT));

        Assert.areEqual('1', baseResponse.getHeader('X-Version'), 'The original should keep its header');
        Assert.areEqual('2', variantResponse.getHeader('X-Version'), 'The clone should have its own header');
        Assert.areEqual('shared body', variantResponse.getBody(), 'The clone should keep the original body');
    }

    // Duplicate requests

    @IsTest
    static void whenRequestRejectsSameRequestTwice() {
        HttpMock.Request request = HttpMock.request().withMethod('GET');

        assertRejectedAsDuplicate('request object', request, request);
    }

    @IsTest
    static void whenRequestRejectsRequestWithEqualCriteria() {
        HttpMock.RequestMatcher matcher = new CompressedRequestMatcher();

        assertRejectedAsDuplicate(
            'endpoint',
            HttpMock.request().withEndpoint(ENDPOINT),
            HttpMock.request().withEndpoint(ENDPOINT)
        );
        assertRejectedAsDuplicate(
            'endpoint pattern',
            HttpMock.request().withEndpointPattern('.*/patients'),
            HttpMock.request().withEndpointPattern('.*/patients')
        );
        assertRejectedAsDuplicate(
            'method in different case',
            HttpMock.request().withMethod('GET'),
            HttpMock.request().withMethod('get')
        );
        assertRejectedAsDuplicate(
            'header',
            HttpMock.request().withHeader('X-Id', '1'),
            HttpMock.request().withHeader('X-Id', '1')
        );
        assertRejectedAsDuplicate(
            'body',
            HttpMock.request().withBody('body'),
            HttpMock.request().withBody('body')
        );
        assertRejectedAsDuplicate(
            'body fragment',
            HttpMock.request().withBodyContaining('body'),
            HttpMock.request().withBodyContaining('body')
        );
        assertRejectedAsDuplicate(
            'JSON body in different key order',
            HttpMock.request().withJsonBody(new Map<String, Object>{ 'a' => 1, 'b' => 2 }),
            HttpMock.request().withJsonBody('{"b": 2, "a": 1}')
        );
        assertRejectedAsDuplicate(
            'custom matcher instance',
            HttpMock.request().withMatcher(matcher),
            HttpMock.request().withMatcher(matcher)
        );
    }

    @IsTest
    static void whenRequestAcceptsRequestsThatDifferInOneCriterion() {
        Map<String, HttpMock.Request> requestsByDifference = new Map<String, HttpMock.Request>{
            'no criteria' => HttpMock.request(),
            'endpoint' => HttpMock.request().withEndpoint(ENDPOINT),
            'endpoint in upper case' => HttpMock.request().withEndpoint(ENDPOINT.toUpperCase()),
            'endpoint pattern' => HttpMock.request().withEndpointPattern('.*/patients'),
            'endpoint pattern in upper case' => HttpMock.request().withEndpointPattern('.*/PATIENTS'),
            'method' => HttpMock.request().withMethod('GET'),
            'header value' => HttpMock.request().withHeader('X-Id', 'a'),
            'header value in upper case' => HttpMock.request().withHeader('X-Id', 'A'),
            'header name in lower case' => HttpMock.request().withHeader('x-id', 'a'),
            'other header name' => HttpMock.request().withHeader('X-Other', 'a'),
            'body' => HttpMock.request().withBody('body'),
            'body in upper case' => HttpMock.request().withBody('BODY'),
            'body fragment' => HttpMock.request().withBodyContaining('body'),
            'body fragment in upper case' => HttpMock.request().withBodyContaining('BODY'),
            'JSON string' => HttpMock.request().withJsonBody('"body"'),
            'JSON string in upper case' => HttpMock.request().withJsonBody('"BODY"'),
            'JSON object' => HttpMock.request().withJsonBody('{"body": 1}'),
            'custom matcher' => HttpMock.request().withMatcher(new CompressedRequestMatcher()),
            'other custom matcher instance' => HttpMock.request().withMatcher(new CompressedRequestMatcher())
        };
        List<String> rejectedDifferences = new List<String>();

        for (String difference : requestsByDifference.keySet()) {
            try {
                mock().whenRequest(requestsByDifference.get(difference)).thenRespond(HttpMock.response());
            } catch (HttpMock.HttpMockException e) {
                rejectedDifferences.add(difference);
            }
        }

        Assert.areEqual(
            new List<String>(),
            rejectedDifferences,
            'Requests that differ in one criterion should not be duplicates'
        );
    }

    // assertAllResponsesReturned

    @IsTest
    static void assertAllResponsesReturnedPassesWhenAllWereReturned() {
        mock().whenRequest(HttpMock.request()).thenRespond(HttpMock.response());
        send(newCall('GET', ENDPOINT));

        HttpMock.instance.assertAllResponsesReturned();

        Assert.areEqual(1, HttpMock.instance.getReceivedRequests().size(), 'The only response should be used');
    }

    @IsTest
    static void assertAllResponsesReturnedPassesWithoutRegisteredRequests() {
        HttpMock.instance.assertAllResponsesReturned();

        Assert.isTrue(HttpMock.instance.getReceivedRequests().isEmpty(), 'No call should be recorded');
    }

    // Validation: mock

    @IsTest
    static void whenRequestRejectsNull() {
        HttpMock.HttpMockException error;

        try {
            mock().whenRequest(null);
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(WHEN_REQUEST_NULL, error?.getMessage(), 'A null request should be rejected');
    }

    @IsTest
    static void thenRespondRejectsCallBeforeWhenRequest() {
        HttpMock.HttpMockException error;

        try {
            mock().thenRespond(HttpMock.response());
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(THEN_RESPOND_FIRST, error?.getMessage(), 'thenRespond() should need a request first');
    }

    @IsTest
    static void thenRespondRejectsNullList() {
        mock().whenRequest(HttpMock.request());
        HttpMock.HttpMockException error;

        try {
            mock().thenRespond((List<HttpMock.Response>) null);
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(NO_RESPONSES, error?.getMessage(), 'A null list should be rejected');
    }

    @IsTest
    static void thenRespondRejectsEmptyList() {
        mock().whenRequest(HttpMock.request());
        HttpMock.HttpMockException error;

        try {
            mock().thenRespond(new List<HttpMock.Response>());
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(NO_RESPONSES, error?.getMessage(), 'An empty list should be rejected');
    }

    @IsTest
    static void thenRespondRejectsNullResponse() {
        mock().whenRequest(HttpMock.request());
        HttpMock.HttpMockException error;

        try {
            mock().thenRespond((HttpMock.Response) null);
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(NULL_RESPONSE, error?.getMessage(), 'A null response should be rejected');
    }

    @IsTest
    static void thenRespondAddsNothingWhenListIsRejected() {
        mock().whenRequest(HttpMock.request());
        HttpMock.HttpMockException error;

        try {
            mock().thenRespond(new List<HttpMock.Response>{
                HttpMock.response().withBody('rejected'),
                null
            });
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }
        mock().thenRespond(HttpMock.response().withBody('accepted'));
        String body = send(newCall('GET', ENDPOINT)).getBody();

        Assert.areEqual(NULL_RESPONSE, error?.getMessage(), 'A list with a null response should be rejected');
        Assert.areEqual('accepted', body, 'No response from the rejected list should be added');
    }

    @IsTest
    static void getReceivedRequestsRejectsUnknownRequest() {
        mock()
            .whenRequest(HttpMock.request().withMethod('GET'))
            .thenRespond(HttpMock.response());
        HttpMock.HttpMockException error;

        try {
            mock().getReceivedRequests(HttpMock.request().withMethod('PATCH'));
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(UNKNOWN_REQUEST, error?.getMessage(), 'A request that was never added should be rejected');
    }

    @IsTest
    static void getReceivedRequestsRejectsNull() {
        mock().whenRequest(HttpMock.request()).thenRespond(HttpMock.response());
        HttpMock.HttpMockException error;

        try {
            mock().getReceivedRequests((HttpMock.Request) null);
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(UNKNOWN_REQUEST, error?.getMessage(), 'A null request should not be found');
    }

    // Validation: request builder

    @IsTest
    static void requestWithHeaderRejectsNullName() {
        HttpMock.HttpMockException error;

        try {
            HttpMock.request().withHeader(null, 'value');
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(HEADER_REQUIRED, error?.getMessage(), 'A null header name should be rejected');
    }

    @IsTest
    static void requestWithHeaderRejectsNullValue() {
        HttpMock.HttpMockException error;

        try {
            HttpMock.request().withHeader('X-Id', null);
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(HEADER_REQUIRED, error?.getMessage(), 'A null header value should be rejected');
    }

    @IsTest
    static void requestWithEndpointPatternRejectsInvalidRegex() {
        HttpMock.HttpMockException error;

        try {
            HttpMock.request().withEndpointPattern('[');
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(INVALID_PATTERN, error?.getMessage(), 'An invalid regex should be rejected');
        Assert.isInstanceOfType(
            error?.getCause(),
            StringException.class,
            'The platform error should be kept as the cause'
        );
    }

    @IsTest
    static void requestWithJsonBodyRejectsInvalidJson() {
        HttpMock.HttpMockException error;

        try {
            HttpMock.request().withJsonBody('{not json');
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(INVALID_JSON, error?.getMessage(), 'Invalid JSON should be rejected');
        Assert.isInstanceOfType(
            error?.getCause(),
            JSONException.class,
            'The platform error should be kept as the cause'
        );
    }

    @IsTest
    static void requestWithJsonBodyRejectsNull() {
        HttpMock.HttpMockException error;

        try {
            HttpMock.request().withJsonBody(null);
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(JSON_NULL, error?.getMessage(), 'A null JSON body should be rejected');
    }

    @IsTest
    static void requestWithJsonBodyRejectsJsonNull() {
        HttpMock.HttpMockException error;

        try {
            HttpMock.request().withJsonBody('null');
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(JSON_NULL, error?.getMessage(), 'JSON null should be rejected');
    }

    // Validation: response builder

    @IsTest
    static void responseWithStatusCodeRejectsNull() {
        HttpMock.HttpMockException error;

        try {
            HttpMock.response().withStatusCode(null);
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(STATUS_CODE_REQUIRED, error?.getMessage(), 'A null status code should be rejected');
    }

    @IsTest
    static void responseWithHeaderRejectsNullName() {
        HttpMock.HttpMockException error;

        try {
            HttpMock.response().withHeader(null, 'value');
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(HEADER_REQUIRED, error?.getMessage(), 'A null header name should be rejected');
    }

    @IsTest
    static void responseWithHeaderRejectsNullValue() {
        HttpMock.HttpMockException error;

        try {
            HttpMock.response().withHeader('X-Id', null);
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(HEADER_REQUIRED, error?.getMessage(), 'A null header value should be rejected');
    }

    // Helpers

    private static HttpMock mock() {
        Test.setMock(HttpCalloutMock.class, HttpMock.instance);
        return HttpMock.instance;
    }

    // A call that matches nothing fails the test with an AssertException that can't be caught,
    // so matching tests also register a fallback that answers every other call.
    private static void mockWithFallback(HttpMock.Request request) {
        mock()
            .whenRequest(request)
            .thenRespond(responsesWithBody(MATCHED, 3))
            .whenRequest(HttpMock.request())
            .thenRespond(responsesWithBody(FALLBACK, 3));
    }

    private static List<HttpMock.Response> responsesWithBody(String body, Integer count) {
        List<HttpMock.Response> responses = new List<HttpMock.Response>();
        for (Integer i = 0; i < count; i++) {
            responses.add(HttpMock.response().withBody(body));
        }
        return responses;
    }

    private static Boolean isMatched(HttpRequest call) {
        return MATCHED.equals(send(call).getBody());
    }

    private static HttpResponse callReturning(HttpMock.Response response) {
        mock().whenRequest(HttpMock.request()).thenRespond(response);
        return send(newCall('GET', ENDPOINT));
    }

    private static void assertRejectedAsDuplicate(
        String criterion,
        HttpMock.Request first,
        HttpMock.Request second
    ) {
        mock().reset().whenRequest(first).thenRespond(HttpMock.response());
        HttpMock.HttpMockException error;

        try {
            mock().whenRequest(second);
        } catch (HttpMock.HttpMockException e) {
            error = e;
        }

        Assert.areEqual(
            DUPLICATE_REQUEST,
            error?.getMessage(),
            'Requests with the same ' + criterion + ' should be duplicates'
        );
    }

    private static HttpRequest newCall(String method, String endpoint) {
        HttpRequest call = new HttpRequest();
        call.setMethod(method);
        call.setEndpoint(endpoint);
        return call;
    }

    private static HttpRequest newCall(String method, String endpoint, String body) {
        HttpRequest call = newCall(method, endpoint);
        call.setBody(body);
        return call;
    }

    private static HttpResponse send(HttpRequest call) {
        return new Http().send(call);
    }

    private class CompressedRequestMatcher implements HttpMock.RequestMatcher {
        public Boolean matches(HttpRequest call) {
            return call.getCompressed();
        }
    }
}
