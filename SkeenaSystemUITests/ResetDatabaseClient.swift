//
// ResetDatabaseClient.swift
// SkeenaSystemUITests
//
// Drop into your UI test target.
// This version does NOT use a JWT.
// It exposes an async API and a blocking wrapper suitable for XCTest setUpWithError().
//

import Foundation

public struct ResetDatabaseResponse: Codable {
    public let success: Bool
    public let dryRun: Bool
    public let timestamp: String
    public let summary: Summary
    public let details: [Detail]?

    public struct Summary: Codable {
        public let totalDeleted: Int?
        public let tablesProcessed: Int?
        public let preservedTables: [String]?
    }

    public struct Detail: Codable {
        public let table: String
        public let deleted: Int
    }
}

public enum ResetDatabaseError: Error, LocalizedError {
    case invalidURL
    case httpError(status: Int, body: String?)
    case network(Error)
    case decoding(Error)
    case timeout
    case unknown

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Reset URL is invalid."
        case .httpError(let status, let body):
            return "HTTP error \(status). Body: \(body ?? "none")"
        case .network(let e):
            return "Network error: \(e.localizedDescription)"
        case .decoding(let e):
            return "Decoding error: \(e.localizedDescription)"
        case .timeout:
            return "Request timed out."
        case .unknown:
            return "Unknown error."
        }
    }
}

public final class ResetDatabaseClient {
    /// Public endpoint for the reset function
    private let endpoint = "PLACEHOLDER_URL/functions/v1/reset-database"
    private let session: URLSession

    /// - Parameters:
    ///   - timeout: request timeout in seconds (default 60s)
    public init(timeout: TimeInterval = 60) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    /// Async/await version
    /// - Parameter dryRun: set to true to preview, false to perform actual reset
    /// - Returns: decoded `ResetDatabaseResponse`
    public func resetDatabase(dryRun: Bool = false) async throws -> ResetDatabaseResponse {
        guard let url = URL(string: endpoint) else {
            throw ResetDatabaseError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Compose body: the API expects an object; include dryRun explicitly
        let body: [String: Any] = ["dryRun": dryRun]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ResetDatabaseError.unknown
            }

            if !(200...299).contains(http.statusCode) {
                let bodyText = String(data: data, encoding: .utf8)
                throw ResetDatabaseError.httpError(status: http.statusCode, body: bodyText)
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let resp = try decoder.decode(ResetDatabaseResponse.self, from: data)
                return resp
            } catch {
                throw ResetDatabaseError.decoding(error)
            }
        } catch is CancellationError {
            throw ResetDatabaseError.timeout
        } catch {
            throw ResetDatabaseError.network(error)
        }
    }

    /// Blocking wrapper that waits synchronously for the async call to complete.
    /// Useful for XCTest `setUpWithError()` if you prefer not to use async XCTest APIs.
    /// - Parameters:
    ///   - dryRun: preview vs actual
    ///   - timeout: overall blocking timeout (seconds). If async call doesn't complete in time, throws `.timeout`.
    public func resetDatabaseBlocking(dryRun: Bool = false, timeout: TimeInterval = 60) throws -> ResetDatabaseResponse {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<ResetDatabaseResponse, Error>!

        Task.detached {
            do {
                let resp = try await self.resetDatabase(dryRun: dryRun)
                result = .success(resp)
            } catch {
                result = .failure(error)
            }
            sem.signal()
        }

        let waitResult = sem.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            throw ResetDatabaseError.timeout
        }

        switch result! {
        case .success(let resp):
            return resp
        case .failure(let error):
            throw error
        }
    }
}
