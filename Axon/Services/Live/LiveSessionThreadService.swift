//
//  LiveSessionThreadService.swift
//  Axon
//
//  Captures Live session conversations and audio for playback and persistence.
//  Converts Live sessions to regular chat threads when closed.
//

import Foundation
import AVFoundation
import Combine

// MARK: - Models

/// A single turn in a Live session conversation
struct LiveSessionTurn: Codable, Identifiable {
    let id: String
    let role: LiveTurnRole
    let transcript: String
    let audioData: Data?  // Raw audio data (optional)
    let audioFileURL: URL?  // Path to saved audio file
    let timestamp: Date
    let durationMs: Int?

    init(
        id: String = UUID().uuidString,
        role: LiveTurnRole,
        transcript: String,
        audioData: Data? = nil,
        audioFileURL: URL? = nil,
        timestamp: Date = Date(),
        durationMs: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.transcript = transcript
        self.audioData = audioData
        self.audioFileURL = audioFileURL
        self.timestamp = timestamp
        self.durationMs = durationMs
    }
}

enum LiveTurnRole: String, Codable {
    case user
    case assistant
}

/// Complete recording of a Live session
struct LiveSessionRecording: Codable, Identifiable {
    let id: String
    let conversationId: String?  // Associated conversation (if any)
    let provider: String  // "gemini", "openai", "mlx"
    let modelId: String
    let voice: String
    let turns: [LiveSessionTurn]
    let startedAt: Date
    let endedAt: Date?
    let totalDurationMs: Int?

    /// Combined audio file for full playback (optional)
    let combinedAudioURL: URL?

    init(
        id: String = UUID().uuidString,
        conversationId: String? = nil,
        provider: String,
        modelId: String,
        voice: String,
        turns: [LiveSessionTurn] = [],
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        totalDurationMs: Int? = nil,
        combinedAudioURL: URL? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.provider = provider
        self.modelId = modelId
        self.voice = voice
        self.turns = turns
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalDurationMs = totalDurationMs
        self.combinedAudioURL = combinedAudioURL
    }
}

// MARK: - Service

/// Service for capturing and managing Live session conversations
@MainActor
final class LiveSessionThreadService: ObservableObject {
    static let shared = LiveSessionThreadService()

    // MARK: - Published State

    /// Whether recording is active
    @Published private(set) var isRecording: Bool = false

    /// Current session turns
    @Published private(set) var turns: [LiveSessionTurn] = []

    /// Current recording (nil if not recording)
    @Published private(set) var currentRecording: LiveSessionRecording?

    /// Playback state
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var playbackProgress: Double = 0.0
    @Published private(set) var currentPlaybackTurnIndex: Int = 0

    // MARK: - Private State

    private var sessionId: String?
    private var conversationId: String?
    private var provider: String = ""
    private var modelId: String = ""
    private var voice: String = ""
    private var sessionStartTime: Date?

    // Audio recording
    private var userAudioChunks: [Data] = []
    private var assistantAudioChunks: [Data] = []
    private var currentUserTranscript: String = ""
    private var currentAssistantTranscript: String = ""
    private var userSpeechStartTime: Date?

    // Audio playback
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var recordingsToPlay: [LiveSessionTurn] = []

    // Storage
    private let fileManager = FileManager.default
    private lazy var recordingsDirectory: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Axon/LiveRecordings", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - Session Management

    /// Start recording a new Live session
    func startSession(
        conversationId: String?,
        provider: String,
        modelId: String,
        voice: String
    ) {
        guard !isRecording else {
            debugLog(.liveSession, "[ThreadService] Already recording, ignoring startSession")
            return
        }

        sessionId = UUID().uuidString
        self.conversationId = conversationId
        self.provider = provider
        self.modelId = modelId
        self.voice = voice
        sessionStartTime = Date()

        turns = []
        userAudioChunks = []
        assistantAudioChunks = []
        currentUserTranscript = ""
        currentAssistantTranscript = ""

        isRecording = true
        debugLog(.liveSession, "[ThreadService] Started recording session: \(sessionId ?? "nil")")
    }

    /// End the current recording session
    func endSession() async -> LiveSessionRecording? {
        guard isRecording, let sessionId = sessionId else {
            debugLog(.liveSession, "[ThreadService] No active session to end")
            return nil
        }

        isRecording = false

        // Finalize any pending turn
        finalizeCurrentUserTurn()
        finalizeCurrentAssistantTurn()

        let endTime = Date()
        let duration = sessionStartTime.map { Int(endTime.timeIntervalSince($0) * 1000) }

        // Create the recording
        let recording = LiveSessionRecording(
            id: sessionId,
            conversationId: conversationId,
            provider: provider,
            modelId: modelId,
            voice: voice,
            turns: turns,
            startedAt: sessionStartTime ?? endTime,
            endedAt: endTime,
            totalDurationMs: duration,
            combinedAudioURL: nil  // Could combine audio files here
        )

        currentRecording = recording

        // Save recording metadata
        await saveRecording(recording)

        debugLog(.liveSession, "[ThreadService] Ended session with \(turns.count) turns")

        // Reset state
        self.sessionId = nil
        sessionStartTime = nil

        return recording
    }

    // MARK: - Audio Capture

    /// Record user audio chunk (called from LiveSessionService)
    func recordUserAudio(buffer: AVAudioPCMBuffer) {
        guard isRecording else { return }

        // Convert buffer to data
        if let data = buffer.toRecordingData() {
            userAudioChunks.append(data)
        }

        // Track speech start time
        if userSpeechStartTime == nil {
            userSpeechStartTime = Date()
        }
    }

    /// Record assistant audio chunk
    func recordAssistantAudio(data: Data) {
        guard isRecording else { return }
        assistantAudioChunks.append(data)
    }

    // MARK: - Transcript Capture

    /// Add user transcript text (may be called incrementally)
    func addUserTranscript(_ text: String) {
        guard isRecording else { return }
        currentUserTranscript = text
    }

    /// Finalize the current user turn (called when user stops speaking)
    func finalizeUserTurn() {
        finalizeCurrentUserTurn()
    }

    private func finalizeCurrentUserTurn() {
        guard !currentUserTranscript.isEmpty else { return }

        let audioData = combineAudioChunks(userAudioChunks)
        let duration = userSpeechStartTime.map { Int(Date().timeIntervalSince($0) * 1000) }

        let turn = LiveSessionTurn(
            role: .user,
            transcript: currentUserTranscript,
            audioData: audioData,
            durationMs: duration
        )

        turns.append(turn)
        debugLog(.liveSession, "[ThreadService] Added user turn: \(currentUserTranscript.prefix(50))...")

        // Reset
        currentUserTranscript = ""
        userAudioChunks = []
        userSpeechStartTime = nil
    }

    /// Add assistant transcript text (may be streamed)
    func addAssistantTranscript(_ text: String, isFinal: Bool = false) {
        guard isRecording else { return }

        if isFinal {
            currentAssistantTranscript = text
            finalizeCurrentAssistantTurn()
        } else {
            // For streaming text, accumulate it
            currentAssistantTranscript += text
        }
    }

    /// Called when user starts speaking - finalize any pending assistant turn
    func onUserStartedSpeaking() {
        guard isRecording else { return }
        // If assistant was speaking/streaming, finalize that turn first
        if !currentAssistantTranscript.isEmpty {
            finalizeCurrentAssistantTurn()
        }
    }

    /// Called when assistant audio playback completes - finalize the turn
    func onAssistantAudioComplete() {
        guard isRecording else { return }
        // Finalize the assistant turn when audio finishes
        if !currentAssistantTranscript.isEmpty {
            finalizeCurrentAssistantTurn()
        }
    }

    /// Finalize the current assistant turn
    func finalizeAssistantTurn() {
        finalizeCurrentAssistantTurn()
    }

    private func finalizeCurrentAssistantTurn() {
        guard !currentAssistantTranscript.isEmpty else { return }

        let audioData = combineAudioChunks(assistantAudioChunks)

        let turn = LiveSessionTurn(
            role: .assistant,
            transcript: currentAssistantTranscript,
            audioData: audioData
        )

        turns.append(turn)
        debugLog(.liveSession, "[ThreadService] Added assistant turn: \(currentAssistantTranscript.prefix(50))...")

        // Reset
        currentAssistantTranscript = ""
        assistantAudioChunks = []
    }

    private func combineAudioChunks(_ chunks: [Data]) -> Data? {
        guard !chunks.isEmpty else { return nil }
        var combined = Data()
        for chunk in chunks {
            combined.append(chunk)
        }
        return combined
    }

    // MARK: - Conversion to Chat Thread

    /// Convert a Live session recording to a regular chat conversation
    func convertToConversation(_ recording: LiveSessionRecording) async throws -> Conversation {
        let conversationService = ConversationService.shared
        let syncManager = ConversationSyncManager.shared

        // Generate a title from the first user turn
        let title = generateTitle(from: recording)

        // Create a new conversation through ConversationService (persists to Core Data)
        let conversation = try conversationService.createConversationOffline(title: title)
        let conversationId = conversation.id

        debugLog(.liveSession, "[ThreadService] Created persisted conversation: \(conversationId)")

        // Create messages from turns
        var messages: [Message] = []
        for turn in recording.turns {
            let message = Message(
                id: turn.id,
                conversationId: conversationId,
                role: turn.role == .user ? .user : .assistant,
                content: turn.transcript,
                hiddenReason: nil,
                timestamp: turn.timestamp,
                tokens: nil,
                artifacts: nil,
                toolCalls: nil,
                isStreaming: false,
                modelName: recording.modelId,
                providerName: recording.provider,
                attachments: nil,
                groundingSources: nil,
                memoryOperations: nil,
                reasoning: nil,
                editHistory: nil,
                currentVersion: nil,
                contextDebugInfo: nil,
                liveToolCalls: nil,
                isDeleted: nil
            )
            messages.append(message)
        }

        // Save messages to Core Data
        if !messages.isEmpty {
            try await syncManager.saveMessagesToCoreData(messages, conversationId: conversationId)
            debugLog(.liveSession, "[ThreadService] Saved \(messages.count) messages from Live session")
        }

        // Update conversation with message count
        let updatedConversation = Conversation(
            id: conversation.id,
            userId: conversation.userId,
            title: title,
            projectId: conversation.projectId,
            createdAt: recording.startedAt,
            updatedAt: recording.endedAt ?? Date(),
            messageCount: messages.count,
            lastMessageAt: recording.turns.last?.timestamp,
            archived: false,
            summary: nil,
            lastMessage: messages.last?.content,
            tags: ["live-session"],
            isPinned: false,
            isPrivate: false
        )

        // Save updated conversation metadata
        try await syncManager.saveConversationsToCoreData([updatedConversation])

        debugLog(.liveSession, "[ThreadService] ✅ Persisted Live session as conversation with \(messages.count) messages")

        return updatedConversation
    }

    private func generateTitle(from recording: LiveSessionRecording) -> String {
        // Use first user message as title (truncated)
        if let firstUserTurn = recording.turns.first(where: { $0.role == .user }) {
            let text = firstUserTurn.transcript
            if text.count > 50 {
                return String(text.prefix(47)) + "..."
            }
            return text
        }
        return "Live Session - \(recording.startedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: - Playback

    /// Play back a Live session recording
    func playRecording(_ recording: LiveSessionRecording) {
        guard !recording.turns.isEmpty else {
            debugLog(.liveSession, "[ThreadService] No turns to play")
            return
        }

        recordingsToPlay = recording.turns
        currentPlaybackTurnIndex = 0
        isPlaying = true
        playbackProgress = 0.0

        playNextTurn()
    }

    /// Stop playback
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        playbackProgress = 0.0
        currentPlaybackTurnIndex = 0
        recordingsToPlay = []
    }

    /// Pause/resume playback
    func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
        } else if audioPlayer != nil {
            audioPlayer?.play()
            isPlaying = true
        }
    }

    private func playNextTurn() {
        guard currentPlaybackTurnIndex < recordingsToPlay.count else {
            // Playback complete
            stopPlayback()
            return
        }

        let turn = recordingsToPlay[currentPlaybackTurnIndex]

        // Play audio if available
        if let audioData = turn.audioData {
            playAudioData(audioData) { [weak self] in
                self?.currentPlaybackTurnIndex += 1
                self?.playNextTurn()
            }
        } else {
            // No audio - just advance (with a small delay for text display)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.currentPlaybackTurnIndex += 1
                self?.playNextTurn()
            }
        }

        // Update progress
        playbackProgress = Double(currentPlaybackTurnIndex + 1) / Double(recordingsToPlay.count)
    }

    private func playAudioData(_ data: Data, completion: @escaping () -> Void) {
        do {
            // Determine audio format based on provider
            // Gemini/OpenAI use 24kHz Int16 PCM
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!

            // Convert raw PCM to playable format
            if let buffer = data.toPCMBuffer(format: format) {
                // Write to temp file for AVAudioPlayer
                let tempURL = recordingsDirectory.appendingPathComponent("temp_playback.wav")
                try writeWAVFile(buffer: buffer, to: tempURL)

                audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                audioPlayer?.delegate = AudioPlayerDelegate(completion: completion)
                audioPlayer?.play()
            } else {
                completion()
            }
        } catch {
            debugLog(.liveSession, "[ThreadService] Playback error: \(error.localizedDescription)")
            completion()
        }
    }

    private func writeWAVFile(buffer: AVAudioPCMBuffer, to url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        try file.write(from: buffer)
    }

    // MARK: - Storage

    private func saveRecording(_ recording: LiveSessionRecording) async {
        let fileURL = recordingsDirectory.appendingPathComponent("\(recording.id).json")

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recording)
            try data.write(to: fileURL)
            debugLog(.liveSession, "[ThreadService] Saved recording to \(fileURL.lastPathComponent)")
        } catch {
            debugLog(.liveSession, "[ThreadService] Failed to save recording: \(error.localizedDescription)")
        }
    }

    /// Load a saved recording
    func loadRecording(id: String) async -> LiveSessionRecording? {
        let fileURL = recordingsDirectory.appendingPathComponent("\(id).json")

        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(LiveSessionRecording.self, from: data)
        } catch {
            debugLog(.liveSession, "[ThreadService] Failed to load recording: \(error.localizedDescription)")
            return nil
        }
    }

    /// List all saved recordings
    func listRecordings() async -> [LiveSessionRecording] {
        do {
            let files = try fileManager.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }

            var recordings: [LiveSessionRecording] = []
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for file in files {
                if let data = try? Data(contentsOf: file),
                   let recording = try? decoder.decode(LiveSessionRecording.self, from: data) {
                    recordings.append(recording)
                }
            }

            return recordings.sorted { $0.startedAt > $1.startedAt }
        } catch {
            return []
        }
    }

    /// Delete a recording
    func deleteRecording(id: String) async {
        let fileURL = recordingsDirectory.appendingPathComponent("\(id).json")
        try? fileManager.removeItem(at: fileURL)
    }
}

// MARK: - Audio Player Delegate

private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.completion()
        }
    }
}

// MARK: - AVAudioPCMBuffer Extension

extension AVAudioPCMBuffer {
    /// Convert buffer to raw Data for recording purposes
    func toRecordingData() -> Data? {
        guard let channelData = floatChannelData else { return nil }
        let frameLength = Int(self.frameLength)
        return Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)
    }
}
