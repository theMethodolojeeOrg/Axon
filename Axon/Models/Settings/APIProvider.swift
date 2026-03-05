//
//  APIProvider.swift
//  Axon
//
//  API provider enum for key storage and service calls
//

import Foundation

// MARK: - API Provider

enum APIProvider: String, CaseIterable, Identifiable {
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case xai = "xai"
    case elevenlabs = "elevenlabs"
    case perplexity = "perplexity"
    case deepseek = "deepseek"
    case zai = "zai"
    case minimax = "minimax"
    case mistral = "mistral"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .xai: return "xAI"
        case .elevenlabs: return "ElevenLabs"
        case .perplexity: return "Perplexity"
        case .deepseek: return "DeepSeek"
        case .zai: return "Z.ai (Zhipu)"
        case .minimax: return "MiniMax"
        case .mistral: return "Mistral AI"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .gemini: return "AIza..."
        case .xai: return "xai-..."
        case .elevenlabs: return "sk_..."
        case .perplexity: return "pplx-..."
        case .deepseek: return "sk-..."
        case .zai: return "..."
        case .minimax: return "..."
        case .mistral: return "..."
        }
    }

    var infoURL: URL? {
        switch self {
        case .openai: return URL(string: "https://platform.openai.com/account/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/account/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .xai: return URL(string: "https://console.x.ai")
        case .elevenlabs: return URL(string: "https://elevenlabs.io/app/settings/api-keys")
        case .perplexity: return URL(string: "https://www.perplexity.ai/settings/api")
        case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")
        case .zai: return URL(string: "https://bigmodel.cn/usercenter/apikeys")
        case .minimax: return URL(string: "https://platform.minimax.io/user-center/basic-information/interface-key")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        }
    }

    var description: String {
        switch self {
        case .openai: return "Required for GPT models"
        case .anthropic: return "Required for Claude models"
        case .gemini: return "Required for Gemini models"
        case .xai: return "Required for Grok models"
        case .elevenlabs: return "Required for text-to-speech"
        case .perplexity: return "Required for Sonar models (online search)"
        case .deepseek: return "Required for DeepSeek models"
        case .zai: return "Required for GLM models"
        case .minimax: return "Required for MiniMax M2 models"
        case .mistral: return "Required for Mistral and Pixtral models"
        }
    }
}
