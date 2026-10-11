# HttpMock

A configurable `HttpCalloutMock` for Apex tests. Describe the calls your code should make, give each one
its responses, and check afterwards what was called and with what.

```apex
HttpMock.instance
    .whenRequest(HttpMock.request()
        .withMethod('GET')
        .withEndpoint('callout:ExampleApi/patients/42'))
    .thenRespond(HttpMock.response()
        .withJsonBody(new Map<String, Object>{ 'id' => 42, 'name' => 'Ada' }));
Test.setMock(HttpCalloutMock.class, HttpMock.instance);

Patient patient = new PatientService().getPatient(42);

Assert.areEqual('Ada', patient.name);
HttpMock.instance.assertAllResponsesReturned();
```

- One mock for every callout in a test, without writing a mock class per test.
- Match calls by endpoint, endpoint pattern, method, headers, body, JSON body or your own matcher.
- Return a sequence of responses, including exceptions, to test retries and error handling.
- Read back the calls your code made to assert on their bodies and headers.

## Install

Copy `HttpMock.cls` and `HttpMockTest.cls` (with their `-meta.xml` files) from
[`force-app/main/default/classes`](force-app/main/default/classes) into your project, or deploy them
from a clone of this repository:

```sh
sf project deploy start --source-dir force-app --target-org <your-org>
```

`HttpMock` isn't annotated with `@IsTest`, so it counts toward your org's code coverage. Deploy
`HttpMockTest` with it: the tests cover every line except the ones that fail a test on purpose.

## Usage

### Describe the calls

`whenRequest()` adds a request; `thenRespond()` adds responses to the request added just before it.
Chain them for as many requests as the test needs, then register the mock with `Test.setMock()`.

```apex
HttpMock.Request createPatient = HttpMock.request()
    .withMethod('POST')
    .withEndpoint('callout:ExampleApi/patients');

HttpMock.instance
    .whenRequest(createPatient)
    .thenRespond(HttpMock.response()
        .withStatusCode(201))
    .whenRequest(HttpMock.request()
        .withMethod('GET'))
    .thenRespond(HttpMock.response()
        .withJsonBody(new Map<String, Object>{ 'id' => 42 }));
Test.setMock(HttpCalloutMock.class, HttpMock.instance);
```

`HttpMock.instance` is static, so each test method starts with an empty mock. Call `reset()` to start
over within a test.

### Match requests

A call matches a request when every criterion set on the request matches. Criteria you don't set match
anything, so `HttpMock.request()` on its own matches every call.

| Method                         | Matches                                                                      |
| ------------------------------ | ---------------------------------------------------------------------------- |
| `withEndpoint(String)`         | The exact endpoint, including the query string.                              |
| `withEndpointPattern(String)`  | A regular expression that matches the whole endpoint.                        |
| `withMethod(String)`           | The HTTP method, in any case.                                                |
| `withHeader(String, String)`   | A header with this value. Other headers on the call are ignored.             |
| `withBody(String)`             | The exact body.                                                              |
| `withBodyContaining(String)`   | A body that contains this text.                                              |
| `withJsonBody(Object)`         | A JSON body equal to this one, ignoring key order and whitespace.            |
| `withMatcher(RequestMatcher)`  | Calls your `HttpMock.RequestMatcher` accepts.                                |

Text is compared case-sensitively, header names included; only the HTTP method isn't. For
`withJsonBody()`, array order and number format (`1` vs `1.0`) matter. It takes a JSON string or any
value to serialize.

For anything else, implement `HttpMock.RequestMatcher`:

```apex
private class CompressedRequest implements HttpMock.RequestMatcher {
    public Boolean matches(HttpRequest httpRequest) {
        return httpRequest.getCompressed();
    }
}
```

**Order matters.** Requests are checked in the order they were added, and the first one that matches
answers the call, even if it has no responses left. Add specific requests before broader ones.

### Return responses

A response is `200` with no body unless you set otherwise.

| Method                         | Sets                                                                         |
| ------------------------------ | ---------------------------------------------------------------------------- |
| `withStatusCode(Integer)`      | The status code.                                                             |
| `withStatus(String)`           | The status text, such as `'Not Found'`.                                      |
| `withHeader(String, String)`   | A response header.                                                           |
| `withBody(String)`             | A text body.                                                                 |
| `withBodyAsBlob(Blob)`         | A binary body.                                                               |
| `withJsonBody(Object)`         | A JSON body and `Content-Type: application/json`.                            |
| `withException(Exception)`     | An exception thrown to your code instead of a response.                      |

Each response is used once, in order. Pass a list, or call `thenRespond()` again, to answer repeated
calls differently:

```apex
HttpMock.instance
    .whenRequest(createPatient)
    .thenRespond(new List<HttpMock.Response>{
        HttpMock.response()
            .withException(new CalloutException('Read timed out')),
        HttpMock.response()
            .withStatusCode(201)
    });
```

To return the same response several times, add it several times.

### Check the calls

```apex
// every call, in call order
List<HttpRequest> allCalls = HttpMock.instance.getReceivedRequests();

// the calls that one request answered, including ones answered with an exception
HttpRequest retry = HttpMock.instance.getReceivedRequests(createPatient)[1];
Assert.areEqual('{"name":"Ada"}', retry.getBody());

// fails the test if a response was never returned
HttpMock.instance.assertAllResponsesReturned();
```

`getReceivedRequests(request)` finds the request by its criteria, so an equal request built again works
too.

## When the mock fails a test

- **A call matches no request, or its request has no responses left.** The test fails with an assert
  naming the call. Your code can't catch it, so a `try`/`catch` around the callout won't hide a missing
  mock.
- **The setup is wrong.** `HttpMock.HttpMockException` is thrown, for example when you add two requests
  with the same criteria, call `thenRespond()` before `whenRequest()`, or pass invalid JSON or an invalid
  regular expression.

## Copies

Requests and responses are copied when you add them, so changing them afterwards has no effect on the
mock. To build variants, use `deepClone()`: Apex's built-in `clone()` would share the headers map.

```apex
HttpMock.Request createPatient = HttpMock.request()
    .withMethod('POST')
    .withHeader('Content-Type', 'application/json');
HttpMock.Request createVisit = createPatient.deepClone()
    .withEndpoint('callout:ExampleApi/visits');
```

The calls returned by `getReceivedRequests()` are your code's own `HttpRequest` objects, not copies.

## Development

Validate the classes and run their tests against an org without deploying anything:

```sh
sf project deploy validate \
    --source-dir force-app \
    --test-level RunSpecifiedTests \
    --tests HttpMockTest \
    --target-org <your-org>
```

## License

[MIT](LICENSE)
