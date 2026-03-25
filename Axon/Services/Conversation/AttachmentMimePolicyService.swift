//
//  AttachmentMimePolicyService.swift
//  Axon
//
//  Resolves per-provider/model attachment MIME policies and validates attachments.
//

import Foundation

struct AttachmentMimePolicy: Equatable {
    let provider: String
    let modelId: String
    let providerName: String
    let allowedPatternsByType: [MessageAttachment.AttachmentType: [String]]

    func patterns(for type: MessageAttachment.AttachmentType) -> [String] {
        allowedPatternsByType[type] ?? []
    }

    var supportsAnyAttachment: Bool {
        MessageAttachment.AttachmentType.allCases.contains { !patterns(for: $0).isEmpty }
    }
}

struct AttachmentValidationFailure: Equatable, Identifiable {
    let attachmentId: String
    let attachmentName: String
    let attachmentType: MessageAttachment.AttachmentType
    let resolvedMimeType: String
    let reason: String

    var id: String { attachmentId }
}

enum AttachmentValidationResult: Equatable {
    case accepted
    case rejected([AttachmentValidationFailure])
}

enum AttachmentMimePolicyService {
    private static let fallbackMimeByType: [MessageAttachment.AttachmentType: String] = [
        .image: "image/jpeg",
        .document: "application/pdf",
        .audio: "audio/mpeg",
        .video: "video/mp4"
    ]

    private static let mimeAliases: [String: String] = [
        "audio/mp3": "audio/mpeg",
        "video/mov": "video/quicktime",
        "video/avi": "video/x-msvideo",
        "video/mpg": "video/mpeg"
    ]

    private static let extensionMimeMap: [String: String] = [
        // Documents
        "pdf": "application/pdf",
        "txt": "text/plain",
        "text": "text/plain",
        "rtf": "text/rtf",
        "md": "text/markdown",
        "json": "application/json",
        "xml": "application/xml",
        "csv": "text/csv",
        "html": "text/html",
        "css": "text/css",
        "js": "application/javascript",

        // Images
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "gif": "image/gif",
        "webp": "image/webp",
        "heic": "image/heic",
        "heif": "image/heif",

        // Video
        "mp4": "video/mp4",
        "m4v": "video/mp4",
        "mov": "video/quicktime",
        "avi": "video/x-msvideo",
        "mpeg": "video/mpeg",
        "mpg": "video/mpeg",
        "webm": "video/webm",
        "wmv": "video/x-ms-wmv",
        "3gp": "video/3gpp",
        "3gpp": "video/3gpp",

        // Audio
        "wav": "audio/wav",
        "mp3": "audio/mpeg",
        "aiff": "audio/aiff",
        "aif": "audio/aiff",
        "aac": "audio/aac",
        "m4a": "audio/aac",
        "ogg": "audio/ogg",
        "flac": "audio/flac",
        "opus": "audio/opus"
    ]

    private static let allAttachmentTypes: [MessageAttachment.AttachmentType] = [
        .image, .document, .audio, .video
    ]

    static func resolvePolicy(conversationId: String?, settings: AppSettings) -> AttachmentMimePolicy {
        let resolved: ConversationModelResolver.ResolvedProviderModel
        if let conversationId {
            resolved = ConversationModelResolver.resolve(conversationId: conversationId, settings: settings)
        } else {
            resolved = ConversationModelResolver.resolveGlobal(settings: settings)
        }

        return resolvePolicy(
            provider: resolved.normalizedProvider,
            modelId: resolved.modelId,
            providerName: resolved.providerName,
            conversationId: conversationId,
            settings: settings
        )
    }

    static func resolvePolicy(
        provider: String,
        modelId: String,
        providerName: String,
        conversationId: String?,
        settings: AppSettings
    ) -> AttachmentMimePolicy {
        let normalizedProvider = normalizedProviderKey(provider)
        let patternsByType: [MessageAttachment.AttachmentType: [String]]
        switch normalizedProvider {
        case "anthropic":
            patternsByType = policy(
                image: ["image/*"],
                document: ["application/pdf", "text/*"]
            )

        case "openai":
            patternsByType = policy(
                image: ["image/*"],
                document: [],
                audio: supportsOpenAIAudio(modelId: modelId) ? ["audio/*"] : [],
                video: []
            )

        case "gemini":
            patternsByType = policy(
                image: ["image/*"],
                document: ["application/pdf", "text/*"],
                audio: ["audio/*"],
                video: ["video/*"]
            )

        case "grok":
            patternsByType = policy(image: ["image/jpeg", "image/png"])

        case "perplexity", "deepseek", "minimax", "appleFoundation", "localMLX":
            patternsByType = policy()

        case "zai":
            let supportsVision = modelId.lowercased().contains("v")
            patternsByType = policy(image: supportsVision ? ["image/*"] : [])

        case "mistral":
            let supportsVision = modelId.lowercased().contains("pixtral")
            patternsByType = policy(image: supportsVision ? ["image/*"] : [])

        case "openai-compatible":
            // Keep strict transport parity with chat-completions payload builders:
            // OpenAI-compatible transport currently supports image + audio only.
            let rawPolicy = customProviderPolicy(
                conversationId: conversationId,
                settings: settings,
                fallbackModelCode: modelId
            )
            patternsByType = enforceTransportParity(
                rawPolicy,
                provider: normalizedProvider,
                modelId: modelId
            )

        default:
            patternsByType = policy()
        }

        return AttachmentMimePolicy(
            provider: normalizedProvider,
            modelId: modelId,
            providerName: providerName,
            allowedPatternsByType: patternsByType
        )
    }

    static func validate(
        attachments: [MessageAttachment],
        policy: AttachmentMimePolicy
    ) -> AttachmentValidationResult {
        var failures: [AttachmentValidationFailure] = []

        for attachment in attachments {
            let patterns = policy.patterns(for: attachment.type)
            let mime = resolveMimeType(for: attachment)
            let displayName = attachment.name ?? "\(attachment.type.rawValue) attachment"

            if patterns.isEmpty {
                failures.append(
                    AttachmentValidationFailure(
                        attachmentId: attachment.id,
                        attachmentName: displayName,
                        attachmentType: attachment.type,
                        resolvedMimeType: mime,
                        reason: "This provider/model does not accept \(attachment.type.rawValue) attachments."
                    )
                )
                continue
            }

            if !isMimeAllowed(mime: mime, patterns: patterns) {
                failures.append(
                    AttachmentValidationFailure(
                        attachmentId: attachment.id,
                        attachmentName: displayName,
                        attachmentType: attachment.type,
                        resolvedMimeType: mime,
                        reason: "MIME type '\(mime)' is not accepted for \(attachment.type.rawValue) attachments."
                    )
                )
            }
        }

        return failures.isEmpty ? .accepted : .rejected(failures)
    }

    static func isMimeAllowed(mime: String, patterns: [String]) -> Bool {
        let canonical = canonicalMime(mime)
        if canonical.isEmpty { return false }

        for pattern in normalizeMimePatterns(patterns) {
            if pattern.hasSuffix("/*") {
                let family = String(pattern.dropLast(2))
                if canonical.hasPrefix("\(family)/") {
                    return true
                }
                continue
            }

            if canonical == pattern {
                return true
            }
        }
        return false
    }

    static func resolveMimeType(for attachment: MessageAttachment) -> String {
        if let mime = attachment.mimeType, mime.contains("/") {
            return canonicalMime(mime)
        }

        if let short = attachment.mimeType?.lowercased(),
           let resolved = extensionMimeMap[short] {
            return canonicalMime(resolved)
        }

        if let name = attachment.name?.lowercased() {
            let ext = (name as NSString).pathExtension
            if let resolved = extensionMimeMap[ext] {
                return canonicalMime(resolved)
            }
        }

        return fallbackMimeByType[attachment.type] ?? "application/octet-stream"
    }

    static func parseMimePatternInput(_ input: String) -> [String] {
        input
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalizeMimePatterns(_ patterns: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for raw in patterns {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard isValidMimePattern(trimmed) else { continue }

            let normalized: String
            if trimmed.hasSuffix("/*") {
                normalized = trimmed
            } else {
                normalized = canonicalMime(trimmed)
            }

            if !seen.contains(normalized) {
                seen.insert(normalized)
                output.append(normalized)
            }
        }

        return output
    }

    static func invalidMimePatterns(_ patterns: [String]) -> [String] {
        patterns.filter { !isValidMimePattern($0) }
    }

    static func isValidMimePattern(_ pattern: String) -> Bool {
        let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("/") else { return false }

        let parts = normalized.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        let typePart = String(parts[0])
        let subtypePart = String(parts[1])

        guard isValidMimeToken(typePart) else { return false }
        if subtypePart == "*" { return true }
        return isValidMimeToken(subtypePart)
    }

    static func validationErrorMessage(
        failures: [AttachmentValidationFailure],
        policy: AttachmentMimePolicy
    ) -> String {
        let failedItems = failures
            .map { "\($0.attachmentName) (\($0.resolvedMimeType))" }
            .joined(separator: ", ")
        return "Unsupported attachment MIME type for \(policy.providerName) (\(policy.modelId)): \(failedItems). Accepted MIME types: \(acceptedPatternsSummary(policy: policy))."
    }

    static func acceptedPatternsSummary(policy: AttachmentMimePolicy) -> String {
        var segments: [String] = []
        let byType = policy.allowedPatternsByType

        if let image = byType[.image], !image.isEmpty {
            segments.append("images: \(image.joined(separator: ", "))")
        }
        if let docs = byType[.document], !docs.isEmpty {
            segments.append("documents: \(docs.joined(separator: ", "))")
        }
        if let audio = byType[.audio], !audio.isEmpty {
            segments.append("audio: \(audio.joined(separator: ", "))")
        }
        if let video = byType[.video], !video.isEmpty {
            segments.append("video: \(video.joined(separator: ", "))")
        }

        return segments.isEmpty ? "none" : segments.joined(separator: " | ")
    }

    static func capabilityDescription(policy: AttachmentMimePolicy) -> String {
        if !policy.supportsAnyAttachment {
            return "No attachments supported."
        }
        return "Accepted MIME types: \(acceptedPatternsSummary(policy: policy))."
    }

    // MARK: - Private

    private static func customProviderPolicy(
        conversationId: String?,
        settings: AppSettings,
        fallbackModelCode: String
    ) -> [MessageAttachment.AttachmentType: [String]] {
        guard let (provider, model) = resolveCustomSelection(
            conversationId: conversationId,
            settings: settings,
            preferredModelCode: fallbackModelCode
        ) else {
            return patternsToTypedPolicy(fallbackCustomPatterns(modelCode: fallbackModelCode))
        }

        let configured = normalizeMimePatterns(model?.acceptedAttachmentMimeTypes ?? [])
        if !configured.isEmpty {
            return patternsToTypedPolicy(configured)
        }

        let signature = model?.modelCode ?? provider.providerName
        return patternsToTypedPolicy(fallbackCustomPatterns(modelCode: signature))
    }

    private static func resolveCustomSelection(
        conversationId: String?,
        settings: AppSettings,
        preferredModelCode: String?
    ) -> (provider: CustomProviderConfig, model: CustomModelConfig?)? {
        var selectedProviderId = settings.selectedCustomProviderId
        var selectedModelId = settings.selectedCustomModelId

        if let conversationId {
            let key = "conversation_overrides_\(conversationId)"
            if let data = UserDefaults.standard.data(forKey: key),
               let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {
                selectedProviderId = overrides.customProviderId ?? selectedProviderId
                selectedModelId = overrides.customModelId ?? selectedModelId
            }
        }

        guard let providerId = selectedProviderId,
              let provider = settings.customProviders.first(where: { $0.id == providerId }) else {
            return nil
        }

        let trimmedPreferredModelCode = preferredModelCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = provider.models.first(where: { model in
            guard let preferred = trimmedPreferredModelCode, !preferred.isEmpty else { return false }
            return model.modelCode.caseInsensitiveCompare(preferred) == .orderedSame
        })
            ?? provider.models.first(where: { $0.id == selectedModelId })
            ?? provider.models.first

        return (provider, model)
    }

    private static func fallbackCustomPatterns(modelCode: String) -> [String] {
        let signature = modelCode.lowercased()
        var patterns: [String] = ["image/*"]

        if signature.contains("audio")
            || signature.contains("speech")
            || signature.contains("tts")
            || signature.contains("realtime") {
            patterns.append("audio/*")
        }

        if signature.contains("video") {
            patterns.append("video/*")
        }

        if signature.contains("pdf") || signature.contains("doc") {
            patterns.append("application/pdf")
            patterns.append("text/plain")
        }

        return patterns
    }

    private static func patternsToTypedPolicy(
        _ patterns: [String]
    ) -> [MessageAttachment.AttachmentType: [String]] {
        var byType = policy()
        for pattern in normalizeMimePatterns(patterns) {
            let type = attachmentType(forPattern: pattern)
            if !byType[type, default: []].contains(pattern) {
                byType[type, default: []].append(pattern)
            }
        }
        return byType
    }

    private static func attachmentType(forPattern pattern: String) -> MessageAttachment.AttachmentType {
        let normalized = pattern.lowercased()
        if normalized.hasPrefix("image/") { return .image }
        if normalized.hasPrefix("audio/") { return .audio }
        if normalized.hasPrefix("video/") { return .video }
        return .document
    }

    private static func policy(
        image: [String] = [],
        document: [String] = [],
        audio: [String] = [],
        video: [String] = []
    ) -> [MessageAttachment.AttachmentType: [String]] {
        [
            .image: normalizeMimePatterns(image),
            .document: normalizeMimePatterns(document),
            .audio: normalizeMimePatterns(audio),
            .video: normalizeMimePatterns(video)
        ]
    }

    private static func canonicalMime(_ rawMime: String) -> String {
        let trimmed = rawMime
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let base = trimmed.split(separator: ";", maxSplits: 1).first.map(String.init) ?? trimmed
        return mimeAliases[base] ?? base
    }

    private static func supportsOpenAIAudio(modelId: String) -> Bool {
        let normalized = modelId.lowercased()
        return normalized.contains("4o")
            || normalized.contains("audio")
            || normalized.contains("realtime")
    }

    private static func normalizedProviderKey(_ provider: String) -> String {
        let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "xai" ? "grok" : normalized
    }

    private static func enforceTransportParity(
        _ policyByType: [MessageAttachment.AttachmentType: [String]],
        provider: String,
        modelId: String
    ) -> [MessageAttachment.AttachmentType: [String]] {
        let supportedTypes = transportSupportedAttachmentTypes(provider: provider, modelId: modelId)
        var filtered = policy()

        for type in allAttachmentTypes {
            filtered[type] = supportedTypes.contains(type) ? (policyByType[type] ?? []) : []
        }

        return filtered
    }

    private static func transportSupportedAttachmentTypes(
        provider: String,
        modelId: String
    ) -> Set<MessageAttachment.AttachmentType> {
        switch provider {
        case "openai":
            var supported: Set<MessageAttachment.AttachmentType> = [.image]
            if supportsOpenAIAudio(modelId: modelId) {
                supported.insert(.audio)
            }
            return supported
        case "openai-compatible":
            // Current OpenAI-compatible payload builders only serialize image + audio.
            return [.image, .audio]
        default:
            return Set(allAttachmentTypes)
        }
    }

    private static func isValidMimeToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789!#$&^_.+-")
        return token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

private extension MessageAttachment.AttachmentType {
    static var allCases: [MessageAttachment.AttachmentType] {
        [.image, .document, .audio, .video]
    }
}
