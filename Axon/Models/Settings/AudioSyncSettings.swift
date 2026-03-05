//
//  AudioSyncSettings.swift
//  Axon
//
//  Cross-device audio sync settings
//

import Foundation

// MARK: - Audio Sync Settings

/// Settings for cross-device audio sync
struct AudioSyncSettings: Codable, Equatable, Sendable {
    /// Enable audio sync across devices (follows iCloud sync setting)
    var syncEnabled: Bool = true

    /// Audio quality preference for sync
    var syncQuality: AudioSyncQuality = .original
}

// MARK: - Audio Sync Quality

/// Audio quality options for syncing generated audio
enum AudioSyncQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case original = "original"
    case compressed = "compressed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Original Quality"
        case .compressed: return "Compressed"
        }
    }

    var description: String {
        switch self {
        case .original:
            return "Keep original format (WAV/MP3). Higher quality, larger files."
        case .compressed:
            return "Convert WAV to AAC. Smaller files, slightly reduced quality."
        }
    }

    var icon: String {
        switch self {
        case .original: return "waveform"
        case .compressed: return "arrow.down.right.and.arrow.up.left"
        }
    }
}
