import Foundation
import Combine

final class CostService: ObservableObject {
    static let shared = CostService()

    @Published private(set) var monthlyTotalsUSD: [AIProvider: Double] = [:]
    @Published private(set) var todaysTotalsUSD: [AIProvider: Double] = [:]
    
    // MARK: - Media Generation Costs
    
    @Published private(set) var monthlyImageCostUSD: Double = 0
    @Published private(set) var monthlyTTSCostUSD: Double = 0
    @Published private(set) var monthlyImageCount: Int = 0
    @Published private(set) var monthlyTTSCount: Int = 0
    
    @Published private(set) var todayImageCostUSD: Double = 0
    @Published private(set) var todayTTSCostUSD: Double = 0

    // Aggregate total for this month across all providers
    var totalThisMonthUSD: Double {
        monthlyTotalsUSD.values.reduce(0, +) + monthlyImageCostUSD + monthlyTTSCostUSD
    }
    
    var chatCostThisMonthUSD: Double {
        monthlyTotalsUSD.values.reduce(0, +)
    }

    var totalThisMonthUSDFriendly: String {
        let total = totalThisMonthUSD
        if total < 0.01 { return "$0.00" }
        return "$" + String(format: "%.2f", total)
    }

    private let calendar = Calendar.current

    private init() {
        // Initialize with zeroes for all providers for predictable UI
        AIProvider.allCases.forEach { provider in
            monthlyTotalsUSD[provider] = 0
            todaysTotalsUSD[provider] = 0
        }
    }

    // MARK: - Public API

    func recordUsage(provider: AIProvider, modelId: String, inputTokens: Int, outputTokens: Int, cachedInputTokens: Int = 0, usedContextTokens: Int? = nil, inputIsAudio: Bool = false) {
        // First try to get pricing from UnifiedModelRegistry (JSON-based, dynamic)
        let pricing: ModelPricing
        if let registryPricing = UnifiedModelRegistry.shared.pricing(for: modelId) {
            pricing = registryPricing
        } else if let configPricing = ModelConfigurationService.shared.pricing(for: modelId) {
            // Try ModelConfigurationService as secondary source
            pricing = configPricing
        } else {
            // Fall back to static registry for backward compatibility
            let canonical = PricingKeyResolver.canonicalKey(for: modelId) ?? PricingKeyResolver.defaultKey(for: provider)
            pricing = PricingRegistry.price(for: canonical, usedContextTokens: usedContextTokens, inputIsAudio: inputIsAudio)
        }

        let inputCost = (Double(inputTokens) / 1_000_000.0) * pricing.inputPerMTokUSD
        let outputCost = (Double(outputTokens) / 1_000_000.0) * pricing.outputPerMTokUSD
        let cachedCost = pricing.cachedInputPerMTokUSD.map { (Double(cachedInputTokens) / 1_000_000.0) * $0 } ?? 0

        let total = inputCost + outputCost + cachedCost

        // Update totals
        monthlyTotalsUSD[provider, default: 0] += total
        if isToday(Date()) {
            todaysTotalsUSD[provider, default: 0] += total
        }
        objectWillChange.send()
    }
    
    // MARK: - Media Generation Recording
    
    /// Record an image generation cost
    func recordImageGeneration(quality: ImageQuality, size: ImageSize) {
        let cost = MediaCostEstimator.estimateImageCost(quality: quality, size: size)
        monthlyImageCostUSD += cost
        monthlyImageCount += 1
        if isToday(Date()) {
            todayImageCostUSD += cost
        }
        objectWillChange.send()
    }
    
    /// Record a TTS generation cost
    func recordTTSGeneration(provider: TTSProvider, characterCount: Int) {
        let cost = MediaCostEstimator.estimateTTSCost(provider: provider, characterCount: characterCount)
        monthlyTTSCostUSD += cost
        monthlyTTSCount += 1
        if isToday(Date()) {
            todayTTSCostUSD += cost
        }
        objectWillChange.send()
    }

    // MARK: - Helpers

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }
}

// MARK: - Media Cost Estimator

struct MediaCostEstimator {
    // OpenAI Image pricing (per image)
    static let openAIImagePricing: [ImageQuality: [ImageSize: Double]] = [
        .low: [.square1024: 0.01, .landscape1536: 0.013, .portrait1536: 0.013, .auto: 0.01],
        .medium: [.square1024: 0.04, .landscape1536: 0.05, .portrait1536: 0.05, .auto: 0.04],
        .high: [.square1024: 0.17, .landscape1536: 0.20, .portrait1536: 0.20, .auto: 0.17],
        .auto: [.square1024: 0.04, .landscape1536: 0.05, .portrait1536: 0.05, .auto: 0.04]
    ]
    
    // TTS pricing (per 1,000 characters)
    static let ttsPricingPerKChars: [TTSProvider: Double] = [
        .openai: 0.015,      // tts-1 standard
        .elevenlabs: 0.20,   // API standard rate
        .gemini: 0.0         // Currently free tier
    ]
    
    /// Estimate cost for image generation
    static func estimateImageCost(quality: ImageQuality, size: ImageSize) -> Double {
        openAIImagePricing[quality]?[size] ?? openAIImagePricing[.auto]?[.square1024] ?? 0.04
    }
    
    /// Estimate cost for TTS generation
    static func estimateTTSCost(provider: TTSProvider, characterCount: Int) -> Double {
        let perKChars = ttsPricingPerKChars[provider] ?? 0.015
        return (Double(characterCount) / 1000.0) * perKChars
    }
    
    /// Format cost as friendly string
    static func formattedCost(_ cost: Double) -> String {
        if cost < 0.001 { return "<$0.01" }
        if cost < 0.01 { return String(format: "~$%.3f", cost) }
        return String(format: "~$%.2f", cost)
    }
}

// MARK: - Pricing Models

struct ModelPricing: Codable, Equatable {
    let inputPerMTokUSD: Double
    let outputPerMTokUSD: Double
    let cachedInputPerMTokUSD: Double?
    let notes: String?
}

enum CanonicalModelKey: String, CaseIterable, Hashable, Codable {
    // Anthropic
    case claudeOpus45 = "claude-opus-4.5"
    case claudeSonnet45 = "claude-sonnet-4.5"
    case claudeHaiku45 = "claude-haiku-4.5"
    case claudeOpus41 = "claude-opus-4.1"
    case claudeSonnet4 = "claude-sonnet-4"
    case claudeOpus4 = "claude-opus-4"

    // OpenAI
    case gpt52 = "gpt-5.2"
    case gpt51 = "gpt-5.1"
    case gpt51ChatLatest = "gpt-5.1-chat-latest"
    case gpt5 = "gpt-5"
    case gpt5Mini = "gpt-5-mini"
    case gpt5Nano = "gpt-5-nano"
    case o3 = "o3"
    case o3Pro = "o3-pro"
    case o4Mini = "o4-mini"
    case o3Mini = "o3-mini"
    case o1 = "o1"
    case o1Mini = "o1-mini"
    case gpt41 = "gpt-4.1"
    case gpt41Mini = "gpt-4.1-mini"
    case gpt41Nano = "gpt-4.1-nano"
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"

    // Gemini
    case gemini3ProPreview = "gemini-3-pro-preview"
    case gemini25FlashLite = "gemini-2.5-flash-lite-preview"
    case gemini25Pro = "gemini-2.5-pro"
    case gemini25Flash = "gemini-2.5-flash"

    // xAI (Grok)
    case grok4FastReasoning = "grok-4-fast-reasoning"
    case grok4FastNonReasoning = "grok-4-fast-non-reasoning"
    case grokCodeFast1 = "grok-code-fast-1"
    case grok40709 = "grok-4-0709"
    case grok3Mini = "grok-3-mini"
    case grok3 = "grok-3"

    // Perplexity
    case sonarReasoningPro = "sonar-reasoning-pro"
    case sonarReasoning = "sonar-reasoning"
    case sonarPro = "sonar-pro"
    case sonar = "sonar"

    // DeepSeek
    case deepseekReasoner = "deepseek-reasoner"
    case deepseekChat = "deepseek-chat"

    // Z.ai (Zhipu AI)
    case glm47 = "glm-4.7"
    case glm46 = "glm-4.6"
    case glm46v = "glm-4.6v"
    case glm46vFlashX = "glm-4.6v-flashx"
    case glm46vFlash = "glm-4.6v-flash"
    case glm45 = "glm-4.5"
    case glm45v = "glm-4.5v"
    case glm45Air = "glm-4.5-air"
    case glm45Flash = "glm-4.5-flash"

    // MiniMax
    case minimaxM2 = "minimax-m2"
    case minimaxM2Stable = "minimax-m2-stable"

    // Mistral
    case mistralLarge = "mistral-large"
    case pixtralLarge = "pixtral-large"
    case pixtral12b = "pixtral-12b"
    case codestral = "codestral"
}

struct PricingRegistry {
    static let base: [CanonicalModelKey: ModelPricing] = [
        // Anthropic
        .claudeOpus45: .init(inputPerMTokUSD: 15.00, outputPerMTokUSD: 75.00, cachedInputPerMTokUSD: nil, notes: nil),
        .claudeSonnet45: .init(inputPerMTokUSD: 3.00, outputPerMTokUSD: 15.00, cachedInputPerMTokUSD: nil, notes: nil),
        .claudeHaiku45: .init(inputPerMTokUSD: 1.00, outputPerMTokUSD: 5.00, cachedInputPerMTokUSD: nil, notes: nil),
        .claudeOpus41: .init(inputPerMTokUSD: 15.00, outputPerMTokUSD: 75.00, cachedInputPerMTokUSD: nil, notes: nil),
        .claudeSonnet4: .init(inputPerMTokUSD: 3.00, outputPerMTokUSD: 15.00, cachedInputPerMTokUSD: nil, notes: nil),
        .claudeOpus4: .init(inputPerMTokUSD: 15.00, outputPerMTokUSD: 75.00, cachedInputPerMTokUSD: nil, notes: nil),

        // OpenAI
        .gpt52: .init(inputPerMTokUSD: 1.50, outputPerMTokUSD: 12.00, cachedInputPerMTokUSD: 0.15, notes: nil),
        .gpt51: .init(inputPerMTokUSD: 1.25, outputPerMTokUSD: 10.00, cachedInputPerMTokUSD: 0.13, notes: nil),
        .gpt51ChatLatest: .init(inputPerMTokUSD: 1.25, outputPerMTokUSD: 10.00, cachedInputPerMTokUSD: 0.13, notes: nil),
        .gpt5: .init(inputPerMTokUSD: 1.25, outputPerMTokUSD: 10.00, cachedInputPerMTokUSD: 0.125, notes: nil),
        .gpt5Mini: .init(inputPerMTokUSD: 0.25, outputPerMTokUSD: 2.00, cachedInputPerMTokUSD: 0.025, notes: nil),
        .gpt5Nano: .init(inputPerMTokUSD: 0.05, outputPerMTokUSD: 0.40, cachedInputPerMTokUSD: 0.005, notes: nil),
        .o3: .init(inputPerMTokUSD: 2.00, outputPerMTokUSD: 8.00, cachedInputPerMTokUSD: 0.50, notes: nil),
        .o3Pro: .init(inputPerMTokUSD: 20.00, outputPerMTokUSD: 80.00, cachedInputPerMTokUSD: nil, notes: nil),
        .o4Mini: .init(inputPerMTokUSD: 1.10, outputPerMTokUSD: 4.40, cachedInputPerMTokUSD: 0.275, notes: nil),
        .o3Mini: .init(inputPerMTokUSD: 1.10, outputPerMTokUSD: 4.40, cachedInputPerMTokUSD: 0.55, notes: nil),
        .o1: .init(inputPerMTokUSD: 15.00, outputPerMTokUSD: 60.00, cachedInputPerMTokUSD: nil, notes: nil),
        .o1Mini: .init(inputPerMTokUSD: 1.10, outputPerMTokUSD: 4.40, cachedInputPerMTokUSD: 0.55, notes: nil),
        .gpt41: .init(inputPerMTokUSD: 2.00, outputPerMTokUSD: 8.00, cachedInputPerMTokUSD: 0.50, notes: nil),
        .gpt41Mini: .init(inputPerMTokUSD: 0.40, outputPerMTokUSD: 1.60, cachedInputPerMTokUSD: 0.10, notes: nil),
        .gpt41Nano: .init(inputPerMTokUSD: 0.10, outputPerMTokUSD: 0.40, cachedInputPerMTokUSD: 0.025, notes: nil),
        .gpt4o: .init(inputPerMTokUSD: 2.50, outputPerMTokUSD: 10.00, cachedInputPerMTokUSD: 1.25, notes: nil),
        .gpt4oMini: .init(inputPerMTokUSD: 0.15, outputPerMTokUSD: 0.60, cachedInputPerMTokUSD: 0.075, notes: nil),

        // Gemini
        .gemini3ProPreview: .init(inputPerMTokUSD: 2.00, outputPerMTokUSD: 12.00, cachedInputPerMTokUSD: 0.20, notes: "≤200K tier"),
        .gemini25FlashLite: .init(inputPerMTokUSD: 0.10, outputPerMTokUSD: 0.40, cachedInputPerMTokUSD: 0.01, notes: "Text/img/video; $0.30 input for audio"),
        .gemini25Pro: .init(inputPerMTokUSD: 1.25, outputPerMTokUSD: 10.00, cachedInputPerMTokUSD: nil, notes: "≤200K tier"),
        .gemini25Flash: .init(inputPerMTokUSD: 0.30, outputPerMTokUSD: 2.50, cachedInputPerMTokUSD: nil, notes: "Text/img/video; $1.00 input for audio"),

        // xAI (Grok)
        .grok4FastReasoning: .init(inputPerMTokUSD: 0.20, outputPerMTokUSD: 0.75, cachedInputPerMTokUSD: 0.05, notes: "≤128K tier"),
        .grok4FastNonReasoning: .init(inputPerMTokUSD: 0.20, outputPerMTokUSD: 0.50, cachedInputPerMTokUSD: 0.05, notes: "≤128K tier"),
        .grokCodeFast1: .init(inputPerMTokUSD: 0.20, outputPerMTokUSD: 1.50, cachedInputPerMTokUSD: 0.05, notes: nil),
        .grok40709: .init(inputPerMTokUSD: 3.00, outputPerMTokUSD: 15.00, cachedInputPerMTokUSD: 0.75, notes: nil),
        .grok3Mini: .init(inputPerMTokUSD: 0.30, outputPerMTokUSD: 0.50, cachedInputPerMTokUSD: nil, notes: nil),
        .grok3: .init(inputPerMTokUSD: 3.00, outputPerMTokUSD: 15.00, cachedInputPerMTokUSD: nil, notes: nil),

        // Perplexity (note: also charges per-request for search, not tracked here)
        .sonarReasoningPro: .init(inputPerMTokUSD: 2.00, outputPerMTokUSD: 8.00, cachedInputPerMTokUSD: nil, notes: "Online search + reasoning"),
        .sonarReasoning: .init(inputPerMTokUSD: 1.00, outputPerMTokUSD: 5.00, cachedInputPerMTokUSD: nil, notes: "Online search + reasoning"),
        .sonarPro: .init(inputPerMTokUSD: 3.00, outputPerMTokUSD: 15.00, cachedInputPerMTokUSD: nil, notes: "Online search"),
        .sonar: .init(inputPerMTokUSD: 1.00, outputPerMTokUSD: 1.00, cachedInputPerMTokUSD: nil, notes: "Online search"),

        // DeepSeek (cache hit pricing significantly lower)
        .deepseekReasoner: .init(inputPerMTokUSD: 0.55, outputPerMTokUSD: 2.19, cachedInputPerMTokUSD: 0.14, notes: "R1 reasoning model"),
        .deepseekChat: .init(inputPerMTokUSD: 0.27, outputPerMTokUSD: 1.10, cachedInputPerMTokUSD: 0.07, notes: "V3 chat model"),

        // Z.ai (Zhipu AI)
        .glm47: .init(inputPerMTokUSD: 0.60, outputPerMTokUSD: 2.20, cachedInputPerMTokUSD: 0.11, notes: "Latest flagship, best coding"),
        .glm46: .init(inputPerMTokUSD: 0.60, outputPerMTokUSD: 2.20, cachedInputPerMTokUSD: 0.11, notes: "Previous flagship"),
        .glm46v: .init(inputPerMTokUSD: 0.30, outputPerMTokUSD: 0.90, cachedInputPerMTokUSD: 0.05, notes: "Flagship vision + thinking"),
        .glm46vFlashX: .init(inputPerMTokUSD: 0.04, outputPerMTokUSD: 0.40, cachedInputPerMTokUSD: 0.004, notes: "Ultra-fast vision"),
        .glm46vFlash: .init(inputPerMTokUSD: 0.00, outputPerMTokUSD: 0.00, cachedInputPerMTokUSD: nil, notes: "Free vision"),
        .glm45: .init(inputPerMTokUSD: 0.60, outputPerMTokUSD: 2.20, cachedInputPerMTokUSD: 0.11, notes: nil),
        .glm45v: .init(inputPerMTokUSD: 0.60, outputPerMTokUSD: 1.80, cachedInputPerMTokUSD: 0.11, notes: "Multimodal"),
        .glm45Air: .init(inputPerMTokUSD: 0.20, outputPerMTokUSD: 1.10, cachedInputPerMTokUSD: 0.03, notes: "Balanced tier"),
        .glm45Flash: .init(inputPerMTokUSD: 0.00, outputPerMTokUSD: 0.00, cachedInputPerMTokUSD: nil, notes: "Free"),

        // MiniMax (extremely low pricing)
        .minimaxM2: .init(inputPerMTokUSD: 0.15, outputPerMTokUSD: 0.60, cachedInputPerMTokUSD: nil, notes: "1M context, agentic"),
        .minimaxM2Stable: .init(inputPerMTokUSD: 0.15, outputPerMTokUSD: 0.60, cachedInputPerMTokUSD: nil, notes: "1M context, stable"),

        // Mistral
        .mistralLarge: .init(inputPerMTokUSD: 2.00, outputPerMTokUSD: 6.00, cachedInputPerMTokUSD: nil, notes: "Flagship"),
        .pixtralLarge: .init(inputPerMTokUSD: 2.00, outputPerMTokUSD: 6.00, cachedInputPerMTokUSD: nil, notes: "Flagship vision"),
        .pixtral12b: .init(inputPerMTokUSD: 0.10, outputPerMTokUSD: 0.10, cachedInputPerMTokUSD: nil, notes: "Edge vision"),
        .codestral: .init(inputPerMTokUSD: 0.20, outputPerMTokUSD: 0.60, cachedInputPerMTokUSD: nil, notes: "Code optimized")
    ]

    static func price(for key: CanonicalModelKey, usedContextTokens: Int? = nil, inputIsAudio: Bool = false) -> ModelPricing {
        switch key {
        case .gemini3ProPreview:
            if let used = usedContextTokens, used > 200_000 {
                return ModelPricing(inputPerMTokUSD: 4.00, outputPerMTokUSD: 18.00, cachedInputPerMTokUSD: 0.40, notes: ">200K tier")
            }
            return base[.gemini3ProPreview]!
        case .gemini25FlashLite:
            if inputIsAudio {
                return ModelPricing(inputPerMTokUSD: 0.30, outputPerMTokUSD: 0.40, cachedInputPerMTokUSD: 0.03, notes: "Audio input")
            }
            return base[.gemini25FlashLite]!
        case .gemini25Pro:
            if let used = usedContextTokens, used > 200_000 {
                return ModelPricing(inputPerMTokUSD: 2.50, outputPerMTokUSD: 15.00, cachedInputPerMTokUSD: nil, notes: ">200K tier")
            }
            return base[.gemini25Pro]!
        case .gemini25Flash:
            if inputIsAudio {
                return ModelPricing(inputPerMTokUSD: 1.00, outputPerMTokUSD: 2.50, cachedInputPerMTokUSD: nil, notes: "Audio input")
            }
            return base[.gemini25Flash]!
        case .grok4FastReasoning:
            if let used = usedContextTokens, used > 128_000 {
                return ModelPricing(inputPerMTokUSD: 0.40, outputPerMTokUSD: 1.00, cachedInputPerMTokUSD: 0.05, notes: ">128K tier")
            }
            return base[.grok4FastReasoning]!
        case .grok4FastNonReasoning:
            if let used = usedContextTokens, used > 128_000 {
                return ModelPricing(inputPerMTokUSD: 0.40, outputPerMTokUSD: 0.50, cachedInputPerMTokUSD: 0.05, notes: ">128K tier")
            }
            return base[.grok4FastNonReasoning]!
        default:
            return base[key]!
        }
    }
}

struct PricingKeyResolver {
    static func canonicalKey(for modelId: String) -> CanonicalModelKey? {
        let lower = modelId.lowercased()
        // Anthropic
        if lower.contains("claude-opus-4-5") { return .claudeOpus45 }
        if lower.contains("claude-sonnet-4-5") { return .claudeSonnet45 }
        if lower.contains("claude-haiku-4-5") { return .claudeHaiku45 }
        if lower.contains("claude-opus-4-1") { return .claudeOpus41 }
        if lower.contains("claude-sonnet-4") { return .claudeSonnet4 }
        if lower.contains("claude-opus-4") { return .claudeOpus4 }
        // OpenAI
        if lower.contains("gpt-5.2") { return .gpt52 }
        if lower.contains("gpt-5.1-chat-latest") { return .gpt51ChatLatest }
        if lower.contains("gpt-5.1") { return .gpt51 }
        if lower.contains("gpt-5-mini") { return .gpt5Mini }
        if lower.contains("gpt-5-nano") { return .gpt5Nano }
        if lower.contains("gpt-5") { return .gpt5 }
        if lower == "o3" || lower.contains("o3-") { return .o3 }
        if lower.contains("o3-pro") { return .o3Pro }
        if lower.contains("o4-mini") { return .o4Mini }
        if lower.contains("o3-mini") { return .o3Mini }
        if lower == "o1" || lower.contains("o1-") { return .o1 }
        if lower.contains("o1-mini") { return .o1Mini }
        if lower.contains("gpt-4.1-nano") { return .gpt41Nano }
        if lower.contains("gpt-4.1-mini") { return .gpt41Mini }
        if lower.contains("gpt-4.1") { return .gpt41 }
        if lower.contains("gpt-4o-mini") { return .gpt4oMini }
        if lower.contains("gpt-4o") { return .gpt4o }
        // Gemini
        if lower.contains("gemini-3-pro-preview") { return .gemini3ProPreview }
        if lower.contains("gemini-2.5-flash-lite-preview") { return .gemini25FlashLite }
        if lower.contains("gemini-2.5-pro") { return .gemini25Pro }
        if lower.contains("gemini-2.5-flash") { return .gemini25Flash }
        // xAI (Grok)
        if lower.contains("grok-4-fast-reasoning") { return .grok4FastReasoning }
        if lower.contains("grok-4-fast-non-reasoning") { return .grok4FastNonReasoning }
        if lower.contains("grok-code-fast-1") { return .grokCodeFast1 }
        if lower.contains("grok-4-0709") { return .grok40709 }
        if lower.contains("grok-3-mini") { return .grok3Mini }
        if lower.contains("grok-3") { return .grok3 }
        // Perplexity
        if lower.contains("sonar-reasoning-pro") { return .sonarReasoningPro }
        if lower.contains("sonar-reasoning") { return .sonarReasoning }
        if lower.contains("sonar-pro") { return .sonarPro }
        if lower == "sonar" || lower.hasPrefix("sonar-") { return .sonar }
        // DeepSeek
        if lower.contains("deepseek-reasoner") || lower.contains("deepseek-r1") { return .deepseekReasoner }
        if lower.contains("deepseek-chat") || lower.contains("deepseek-v3") { return .deepseekChat }
        // Z.ai (Zhipu AI)
        if lower.contains("glm-4.7") { return .glm47 }
        if lower.contains("glm-4.6v-flashx") { return .glm46vFlashX }
        if lower.contains("glm-4.6v-flash") { return .glm46vFlash }
        if lower.contains("glm-4.6v") { return .glm46v }
        if lower.contains("glm-4.6") { return .glm46 }
        if lower.contains("glm-4.5-flash") { return .glm45Flash }
        if lower.contains("glm-4.5-air") { return .glm45Air }
        if lower.contains("glm-4.5v") { return .glm45v }
        if lower.contains("glm-4.5") { return .glm45 }
        // MiniMax
        if lower.contains("minimax-m2-stable") { return .minimaxM2Stable }
        if lower.contains("minimax-m2") { return .minimaxM2 }
        // Mistral
        if lower.contains("mistral-large") { return .mistralLarge }
        if lower.contains("pixtral-large") { return .pixtralLarge }
        if lower.contains("pixtral-12b") { return .pixtral12b }
        if lower.contains("codestral") { return .codestral }
        return nil
    }

    static func defaultKey(for provider: AIProvider) -> CanonicalModelKey {
        switch provider {
        case .anthropic: return .claudeHaiku45
        case .openai: return .gpt5Mini
        case .gemini: return .gemini25Flash
        case .xai: return .grok3Mini
        case .perplexity: return .sonar
        case .deepseek: return .deepseekChat
        case .zai: return .glm47
        case .minimax: return .minimaxM2
        case .mistral: return .codestral
        case .appleFoundation: return .claudeHaiku45  // Apple Intelligence is free, no pricing key needed - fallback for display
        case .localMLX: return .claudeHaiku45  // Local MLX models are free, no pricing key needed - fallback for display
        }
    }
}
