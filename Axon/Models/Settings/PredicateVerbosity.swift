//
//  PredicateVerbosity.swift
//  Axon
//
//  Predicate logging verbosity settings
//

import Foundation

// MARK: - Predicate Verbosity

enum PredicateVerbosity: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal = "minimal"    // Only errors and critical predicates
    case normal = "normal"      // Standard logging
    case verbose = "verbose"    // Full proof trees

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .normal: return "Normal"
        case .verbose: return "Verbose"
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Only errors and critical events"
        case .normal: return "Standard predicate logging"
        case .verbose: return "Full proof trees and all predicates"
        }
    }
}
