import Foundation
import Combine

final class CostService: ObservableObject {
    static let shared = CostService()

    @Published private(set) var monthlyTotalsUSD: [AIProvider: Double] = [:]
    @Published private(set) var todaysTotalsUSD: [AIProvider: Double] = [:]

    // Aggregate total for this month across all providers
    var totalThisMonthUSD: Double {
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
        // Estimate cost based on basic pricing registry
        let canonical = PricingKeyResolver.canonicalKey(for: modelId) ?? PricingKeyResolver.defaultKey(for: provider)
        let pricing = PricingRegistry.price(for: canonical, usedContextTokens: usedContextTokens, inputIsAudio: inputIsAudio)

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

    // MARK: - Helpers

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
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
    case claudeSonnet45 = "claude-sonnet-4.5"
    case claudeHaiku45 = "claude-haiku-4.5"
    case claudeOpus41 = "claude-opus-4.1"
    case claudeSonnet4 = "claude-sonnet-4"
    case claudeOpus4 = "claude-opus-4"

    // OpenAI
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
    case gemini25Pro = "gemini-2.5-pro"
    case gemini25Flash = "gemini-2.5-flash"
}

struct PricingRegistry {
    static let base: [CanonicalModelKey: ModelPricing] = [
        // Anthropic
        .claudeSonnet45: .init(inputPerMTokUSD: 3.00, outputPerMTokUSD: 15.00, cachedInputPerMTokUSD: nil, notes: nil),
        .claudeHaiku45: .init(inputPerMTokUSD: 1.00, outputPerMTokUSD: 5.00, cachedInputPerMTokUSD: nil, notes: nil),
        .claudeOpus41: .init(inputPerMTokUSD: 15.00, outputPerMTokUSD: 75.00, cachedInputPerMTokUSD: nil, notes: nil),
        .claudeSonnet4: .init(inputPerMTokUSD: 3.00, outputPerMTokUSD: 15.00, cachedInputPerMTokUSD: nil, notes: nil),
        .claudeOpus4: .init(inputPerMTokUSD: 15.00, outputPerMTokUSD: 75.00, cachedInputPerMTokUSD: nil, notes: nil),

        // OpenAI
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
        .gemini25Pro: .init(inputPerMTokUSD: 1.25, outputPerMTokUSD: 10.00, cachedInputPerMTokUSD: nil, notes: "≤200K tier"),
        .gemini25Flash: .init(inputPerMTokUSD: 0.30, outputPerMTokUSD: 2.50, cachedInputPerMTokUSD: nil, notes: "Text/img/video; $1.00 input for audio")
    ]

    static func price(for key: CanonicalModelKey, usedContextTokens: Int? = nil, inputIsAudio: Bool = false) -> ModelPricing {
        switch key {
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
        default:
            return base[key]!
        }
    }
}

struct PricingKeyResolver {
    static func canonicalKey(for modelId: String) -> CanonicalModelKey? {
        let lower = modelId.lowercased()
        // Anthropic
        if lower.contains("claude-sonnet-4-5") { return .claudeSonnet45 }
        if lower.contains("claude-haiku-4-5") { return .claudeHaiku45 }
        if lower.contains("claude-opus-4-1") { return .claudeOpus41 }
        if lower.contains("claude-sonnet-4") { return .claudeSonnet4 }
        if lower.contains("claude-opus-4") { return .claudeOpus4 }
        // OpenAI
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
        if lower.contains("gemini-2.5-pro") { return .gemini25Pro }
        if lower.contains("gemini-2.5-flash") { return .gemini25Flash }
        return nil
    }

    static func defaultKey(for provider: AIProvider) -> CanonicalModelKey {
        switch provider {
        case .anthropic: return .claudeSonnet45
        case .openai: return .gpt4o
        case .gemini: return .gemini25Pro
        }
    }
}
