//
//  APIResponse.swift
//  Axon
//
//  Generic response wrappers for Firebase Cloud Functions API
//

import Foundation

// MARK: - Single Item Response

/// Wrapper for single object responses from the API
/// API returns: { "data": { ... } }
struct APIResponse<T: Decodable>: Decodable {
    let data: T
}

// MARK: - List Response

/// Wrapper for list responses with pagination from the API
/// API returns: { "data": [...], "pagination": { ... } }
struct APIListResponse<T: Decodable>: Decodable {
    let data: [T]
    let pagination: PaginationMeta?
}

// MARK: - Pagination Metadata

struct PaginationMeta: Codable {
    let offset: Int
    let limit: Int
    let total: Int
    let hasMore: Bool
}

// MARK: - Error Response

/// Error response from the API
/// API returns: { "error": { "code": "...", "message": "..." } }
struct APIErrorResponse: Decodable {
    let error: APIErrorDetail
}

struct APIErrorDetail: Decodable {
    let code: String
    let message: String
    let details: [String: AnyCodable]?
}
