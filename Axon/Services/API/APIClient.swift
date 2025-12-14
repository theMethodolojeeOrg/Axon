//
//  APIClient.swift
//  Axon
//
//  REST API Client with optional backend support
//  Works with user-configured backend or Firebase
//

import Foundation
import Combine

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    private let session: URLSession
    private var backendConfig: BackendConfig { BackendConfig.shared }

    @Published var isLoading = false
    @Published var error: APIError?

    private var tokenStorage: SecureTokenStorage { SecureTokenStorage.shared }
    private var apiKeysStorage: APIKeysStorage { APIKeysStorage.shared }
    private var settingsStorage: SettingsStorage { SettingsStorage.shared }

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad

        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Backend Availability

    /// Check if backend is configured before making requests
    var isBackendConfigured: Bool {
        backendConfig.isBackendConfigured
    }

    // MARK: - Generic Request Method

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        // Check if backend is configured
        guard let baseURL = backendConfig.apiURL else {
            throw APIError.backendNotConfigured
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        // Split endpoint into path and query string
        let components = endpoint.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(components[0])
        let existingQuery = components.count > 1 ? String(components[1]) : nil

        guard var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        // Parse existing query parameters from endpoint
        var queryItems: [URLQueryItem] = []
        if let existingQuery = existingQuery {
            let pairs = existingQuery.split(separator: "&")
            for pair in pairs {
                let keyValue = pair.split(separator: "=", maxSplits: 1)
                if keyValue.count == 2 {
                    let key = String(keyValue[0])
                    let value = String(keyValue[1])
                    queryItems.append(URLQueryItem(name: key, value: value))
                }
            }
        }
        // Backend API key from token storage (if backend is configured)
        if let apiKey = try? tokenStorage.getApiKey() {
            queryItems.append(URLQueryItem(name: "apiKey", value: apiKey))
            #if DEBUG
            print("[APIClient] Using backend API key: \(apiKey.prefix(10))...")
            #endif
        }
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        // Add auth token if configured (from settings or Keychain)
        if let settings = settingsStorage.loadSettings(),
           let token = settings.backendAuthToken, !token.isEmpty {
            urlRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let token = try? tokenStorage.getIdToken() {
            // Fallback to stored token for backward compatibility
            urlRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add custom headers
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let headers = headers {
            for (key, value) in headers {
                urlRequest.addValue(value, forHTTPHeaderField: key)
            }
        }

        // Add request body
        if let body = body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            urlRequest.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // Log response for debugging
            #if DEBUG
            print("[APIClient] \(method.rawValue) \(url.absoluteString) -> \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("[APIClient] Response: \(responseString.prefix(200))")
            }
            #endif

            // Handle status codes
            switch httpResponse.statusCode {
            case 200...299:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    #if DEBUG
                    print("[APIClient] ❌ Decoding error for type \(T.self): \(error)")

                    // Print detailed error information
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            print("[APIClient] 🔑 Missing key: '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                            print("[APIClient] Context: \(context.debugDescription)")
                        case .typeMismatch(let type, let context):
                            print("[APIClient] 🔀 Type mismatch for type '\(type)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                            print("[APIClient] Context: \(context.debugDescription)")
                        case .valueNotFound(let type, let context):
                            print("[APIClient] ❓ Value not found for type '\(type)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                            print("[APIClient] Context: \(context.debugDescription)")
                        case .dataCorrupted(let context):
                            print("[APIClient] 💥 Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                            print("[APIClient] Context: \(context.debugDescription)")
                        @unknown default:
                            print("[APIClient] Unknown decoding error: \(error)")
                        }
                    }

                    if let responseString = String(data: data, encoding: .utf8) {
                        print("[APIClient] 📄 Full response: \(responseString)")
                    }

                    // Try to decode as generic JSON to see structure
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        print("[APIClient] 📋 Response structure keys: \(json.keys.sorted())")
                        if let memories = json["memories"] as? [[String: Any]], let first = memories.first {
                            print("[APIClient] 🧠 First memory keys: \(first.keys.sorted())")
                        }
                    }
                    #endif
                    throw APIError.decodingError(error.localizedDescription)
                }

            case 401:
                // Token expired or invalid
                print("[APIClient] Unauthorized (401) - check backend auth token")
                throw APIError.unauthorized

            case 403:
                throw APIError.forbidden

            case 404:
                throw APIError.notFound

            case 500...599:
                throw APIError.serverError(httpResponse.statusCode)

            default:
                throw APIError.httpError(httpResponse.statusCode)
            }
        } catch let error as APIError {
            self.error = error
            throw error
        } catch {
            let apiError = APIError.networkError(error.localizedDescription)
            self.error = apiError
            throw apiError
        }
    }

    // MARK: - Wrapped Response Methods

    /// Request that automatically unwraps { "data": T } responses
    func requestWrapped<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        let wrapped: APIResponse<T> = try await request(
            endpoint: endpoint,
            method: method,
            body: body,
            headers: headers
        )
        return wrapped.data
    }

    /// Request for list responses that automatically unwraps { "data": [T] } responses
    func requestWrappedList<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        headers: [String: String]? = nil
    ) async throws -> (items: [T], pagination: PaginationMeta?) {
        let wrapped: APIListResponse<T> = try await request(
            endpoint: endpoint,
            method: method,
            body: body,
            headers: headers
        )
        return (wrapped.data, wrapped.pagination)
    }

    // MARK: - Convenience Methods

    func get<T: Decodable>(_ endpoint: String) async throws -> T {
        try await request(endpoint: endpoint, method: .get)
    }

    func post<T: Decodable>(_ endpoint: String, body: Encodable) async throws -> T {
        try await request(endpoint: endpoint, method: .post, body: body)
    }

    func put<T: Decodable>(_ endpoint: String, body: Encodable) async throws -> T {
        try await request(endpoint: endpoint, method: .put, body: body)
    }

    func delete<T: Decodable>(_ endpoint: String) async throws -> T {
        try await request(endpoint: endpoint, method: .delete)
    }

    func patch<T: Decodable>(_ endpoint: String, body: Encodable) async throws -> T {
        try await request(endpoint: endpoint, method: .patch, body: body)
    }
}

// MARK: - HTTP Methods

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    case forbidden
    case notFound
    case unauthorized
    case serverError(Int)
    case httpError(Int)
    case networkError(String)
    case decodingError(String)
    case tokenRefreshFailed
    case backendNotConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidData:
            return "Invalid data in response"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .unauthorized:
            return "Unauthorized access"
        case .serverError(let code):
            return "Server error: \(code)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .tokenRefreshFailed:
            return "Failed to refresh authentication token"
        case .backendNotConfigured:
            return "No backend configured. Set a backend URL in Settings to enable cloud features."
        }
    }
}
