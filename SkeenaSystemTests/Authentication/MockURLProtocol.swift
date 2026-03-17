import Foundation

/// A tiny URLProtocol-based helper that allows tests to stub network responses.
/// Usage:
/// MockURLProtocol.requestHandler = { request in
///   // optionally assert request properties
///   let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
///   return (resp, jsonData)
/// }
final class MockURLProtocol: URLProtocol {
  /// Set by the test to return a response/data for the incoming request
  /// Throws is also supported (so you can simulate network failures).
  static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

  override class func canInit(with request: URLRequest) -> Bool {
    // Intercept *all* requests in tests when this class is registered
    return true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let handler = MockURLProtocol.requestHandler else {
      let url = request.url ?? URL(string: "https://example.invalid")!
      let resp = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: ["X-Mock": "NoHandler"])!
      client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
      let msg = "MockURLProtocol.requestHandler not set"
      let data = msg.data(using: .utf8)
      if let d = data { client?.urlProtocol(self, didLoad: d) }
      client?.urlProtocolDidFinishLoading(self)
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      if let d = data {
        client?.urlProtocol(self, didLoad: d)
      }
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {
    // Nothing to do for this simple mock
  }
}

