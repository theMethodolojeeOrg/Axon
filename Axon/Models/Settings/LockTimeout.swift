//
//  LockTimeout.swift
//  Axon
//
//  Lock timeout settings for app security
//

import Foundation

// MARK: - Lock Timeout

enum LockTimeout: String, Codable, CaseIterable, Identifiable, Sendable {
    case immediate = "immediate"
    case oneMinute = "1min"
    case fiveMinutes = "5min"
    case fifteenMinutes = "15min"
    case oneHour = "1hour"
    case never = "never"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .immediate: return "Immediately"
        case .oneMinute: return "After 1 minute"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .oneHour: return "After 1 hour"
        case .never: return "Never"
        }
    }

    var seconds: Int {
        switch self {
        case .immediate: return 0
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .oneHour: return 3600
        case .never: return Int.max
        }
    }
}
