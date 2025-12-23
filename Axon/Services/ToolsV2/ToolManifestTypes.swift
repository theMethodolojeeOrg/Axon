//
//  ToolManifestTypes.swift
//  Axon
//
//  Created by Claude Code on 2024-12-19.
//
//  Swift types matching the tool.json manifest schema for the ToolsV2 plugin system.
//

import Foundation
import SwiftUI

// MARK: - Root Manifest

/// The root structure of a tool.json manifest file
struct ToolManifest: Codable, Identifiable, Equatable {
    let version: String
    let tool: ToolDefinition
    let parameters: [String: ToolParameterV2]?
    let inputFormat: ToolInputFormat?
    let execution: ToolExecution
    let ai: ToolAIConfig?
    let ui: ToolUIConfig?
    let sovereignty: ToolSovereigntyConfig?

    var id: String { tool.id }

    /// Default manifest version
    static let currentVersion = "1.0.0"
}

// MARK: - Tool Definition

/// Core tool identity and metadata
struct ToolDefinition: Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let category: ToolCategoryV2
    let icon: ToolIcon?
    let requiresApproval: Bool?
    let trustTierCategory: String?
    let tags: [String]?
    let deprecated: Bool?
    let deprecationMessage: String?

    var effectiveRequiresApproval: Bool {
        requiresApproval ?? false
    }
}

/// Tool category for organization (V2 plugin system)
enum ToolCategoryV2: String, Codable, CaseIterable, Equatable {
    case memory
    case agentState = "agent_state"
    case heartbeat
    case sovereignty
    case subAgents = "sub_agents"
    case temporal
    case discovery
    case notification
    case system
    case provider
    case port
    case custom

    var displayName: String {
        switch self {
        case .memory: return "Memory"
        case .agentState: return "Agent State"
        case .heartbeat: return "Heartbeat"
        case .sovereignty: return "Sovereignty"
        case .subAgents: return "Sub-Agents"
        case .temporal: return "Temporal"
        case .discovery: return "Discovery"
        case .notification: return "Notification"
        case .system: return "System"
        case .provider: return "Provider"
        case .port: return "External App"
        case .custom: return "Custom"
        }
    }

    var sfSymbol: String {
        switch self {
        case .memory: return "brain.head.profile"
        case .agentState: return "list.clipboard"
        case .heartbeat: return "heart.fill"
        case .sovereignty: return "crown.fill"
        case .subAgents: return "person.3.fill"
        case .temporal: return "clock.fill"
        case .discovery: return "magnifyingglass"
        case .notification: return "bell.fill"
        case .system: return "gear"
        case .provider: return "cloud.fill"
        case .port: return "app.connected.to.app.below.fill"
        case .custom: return "star.fill"
        }
    }
}

/// Tool icon configuration
struct ToolIcon: Codable, Equatable {
    let sfSymbol: String?
    let emoji: String?
    let assetName: String?

    var resolvedIcon: String {
        sfSymbol ?? emoji ?? assetName ?? "questionmark.circle"
    }
}

// MARK: - Parameters

/// Parameter definition for tool inputs (V2 plugin system)
/// Using a class to allow recursive references
final class ToolParameterV2: Codable, Equatable {
    let type: ParameterTypeV2
    let required: Bool?
    let description: String?
    let defaultValue: AnyCodableV2?

    // String constraints
    let minLength: Int?
    let maxLength: Int?
    let pattern: String?

    // Number constraints
    let minimum: Double?
    let maximum: Double?

    // Enum constraints
    let `enum`: [String]?
    let enumDescriptions: [String: String]?

    // Array constraints
    let items: ToolParameterV2?
    let minItems: Int?
    let maxItems: Int?

    // Object constraints
    let properties: [String: ToolParameterV2]?

    var isRequired: Bool {
        required ?? false
    }

    enum CodingKeys: String, CodingKey {
        case type, required, description
        case defaultValue = "default"
        case minLength, maxLength, pattern
        case minimum, maximum
        case `enum`, enumDescriptions
        case items, minItems, maxItems
        case properties
    }

    static func == (lhs: ToolParameterV2, rhs: ToolParameterV2) -> Bool {
        lhs.type == rhs.type &&
        lhs.required == rhs.required &&
        lhs.description == rhs.description &&
        lhs.defaultValue == rhs.defaultValue &&
        lhs.minLength == rhs.minLength &&
        lhs.maxLength == rhs.maxLength &&
        lhs.pattern == rhs.pattern &&
        lhs.minimum == rhs.minimum &&
        lhs.maximum == rhs.maximum &&
        lhs.enum == rhs.enum &&
        lhs.enumDescriptions == rhs.enumDescriptions &&
        lhs.items == rhs.items &&
        lhs.minItems == rhs.minItems &&
        lhs.maxItems == rhs.maxItems &&
        lhs.properties == rhs.properties
    }
}

/// Parameter types supported by tools (V2 plugin system)
enum ParameterTypeV2: String, Codable, Equatable {
    case string
    case number
    case integer
    case boolean
    case array
    case object
    case `enum`
}

// MARK: - Input Format

/// How the tool expects input to be formatted
struct ToolInputFormat: Codable, Equatable {
    let style: InputStyle
    let pattern: String?
    let delimiter: String?
    let fields: [String]?

    enum InputStyle: String, Codable, Equatable {
        case json
        case pipeDelimited = "pipe_delimited"
        case keyValue = "key_value"
        case positional
        case freeform
    }
}

// MARK: - Execution

/// How the tool is executed
struct ToolExecution: Codable, Equatable {
    let type: ExecutionType
    let handler: String?
    let pipeline: [PipelineStepV2]?
    let provider: String?
    let urlTemplate: String?
    let urlScheme: String?
    let shortcutName: String?
    let bridgeMethod: String?  // For bridge execution type (e.g., "system/info", "clipboard/read")

    enum ExecutionType: String, Codable, Equatable {
        case internalHandler = "internal_handler"
        case pipeline
        case providerNative = "provider_native"
        case urlScheme = "url_scheme"
        case shortcut
        case bridge  // Routes to connected Mac via bridge protocol
    }
}

/// Pipeline step for pipeline execution type
struct PipelineStepV2: Codable, Equatable {
    let type: PipelineStepTypeV2
    let id: String
    let config: [String: AnyCodableV2]?
    let condition: String?
    let then: [PipelineStepV2]?
    let `else`: [PipelineStepV2]?
    let steps: [PipelineStepV2]?

    enum PipelineStepTypeV2: String, Codable, Equatable {
        case modelCall = "model_call"
        case apiCall = "api_call"
        case transform
        case conditional
        case parallel
        case loop
    }
}

// MARK: - AI Configuration

/// Configuration for AI/model integration
struct ToolAIConfig: Codable, Equatable {
    let systemPromptSection: String?
    let usageExamples: [ToolUsageExample]?
    let whenToUse: [String]?
    let whenNotToUse: [String]?
    let modelHints: ToolModelHints?
}

/// Example usage for AI guidance
struct ToolUsageExample: Codable, Equatable {
    let description: String
    let input: String
    let expectedOutput: String?
}

/// Hints for model behavior
struct ToolModelHints: Codable, Equatable {
    let preferredProviders: [String]?
    let requiredCapabilities: [String]?
    let suggestedTemperature: Double?
}

// MARK: - UI Configuration

/// UI rendering configuration
struct ToolUIConfig: Codable, Equatable {
    let inputForm: ToolInputFormConfig?
    let resultDisplay: ToolResultDisplayConfig?
    let settingsPanel: ToolSettingsPanelConfigV2?
}

/// Input form configuration
struct ToolInputFormConfig: Codable, Equatable {
    let fields: [ToolFormField]?
    let layout: FormLayout?
    let submitLabel: String?

    enum FormLayout: String, Codable, Equatable {
        case vertical
        case horizontal
        case grid
    }
}

/// Form field configuration
struct ToolFormField: Codable, Equatable {
    let param: String
    let widget: WidgetType
    let label: String?
    let placeholder: String?
    let rows: Int?
    let min: Double?
    let max: Double?
    let step: Double?
    let options: [WidgetOption]?
    let showIf: String?

    enum WidgetType: String, Codable, Equatable {
        case textField = "text_field"
        case textarea
        case slider
        case segmented
        case tagInput = "tag_input"
        case toggle
        case picker
        case datePicker = "date_picker"
        case stepper
        case colorPicker = "color_picker"
    }
}

/// Option for picker/segmented widgets
struct WidgetOption: Codable, Equatable {
    let value: String
    let label: String
    let icon: String?
}

/// Result display configuration
struct ToolResultDisplayConfig: Codable, Equatable {
    let sections: [ResultSection]?
    let style: ResultStyle?

    enum ResultStyle: String, Codable, Equatable {
        case card
        case inline
        case modal
        case notification
    }
}

/// Section in result display
struct ResultSection: Codable, Equatable {
    let type: SectionType
    let title: String?
    let source: String?
    let icon: String?
    let style: String?
    let items: [ResultSection]?

    enum SectionType: String, Codable, Equatable {
        case header
        case text
        case code
        case list
        case keyValue = "key_value"
        case divider
        case spacer
        case image
        case link
        case badge
        case progress
    }
}

/// Settings panel configuration
struct ToolSettingsPanelConfigV2: Codable, Equatable {
    let sections: [ToolSettingsSectionV2]?
}

/// Settings section (V2 plugin system)
struct ToolSettingsSectionV2: Codable, Equatable {
    let title: String?
    let footer: String?
    let fields: [ToolFormField]?
}

// MARK: - Sovereignty Configuration

/// Sovereignty/trust tier integration
struct ToolSovereigntyConfig: Codable, Equatable {
    let actionCategory: String
    let approvalDescription: String?
    let scopes: [String]?
    let riskLevel: RiskLevel?

    enum RiskLevel: String, Codable, Equatable {
        case low
        case medium
        case high
        case critical
    }
}

// MARK: - Tool Source

/// Where a tool was loaded from
enum ToolSource: Codable, Equatable {
    case bundled
    case iCloud
    case imported(url: URL)
    case custom

    var displayName: String {
        switch self {
        case .bundled: return "Built-in"
        case .iCloud: return "iCloud"
        case .imported: return "Imported"
        case .custom: return "Custom"
        }
    }

    var isEditable: Bool {
        switch self {
        case .bundled: return false
        case .iCloud, .imported, .custom: return true
        }
    }
}

// MARK: - Loaded Tool

/// A tool manifest with its source and path information
struct LoadedTool: Identifiable, Equatable {
    let manifest: ToolManifest
    let source: ToolSource
    let manifestPath: URL
    let folderPath: URL
    var isEnabled: Bool

    var id: String { manifest.id }
    var name: String { manifest.tool.name }
    var description: String { manifest.tool.description }
    var category: ToolCategoryV2 { manifest.tool.category }
    var icon: String { manifest.tool.icon?.resolvedIcon ?? category.sfSymbol }
}

// MARK: - Tool Index

/// Master index file structure (_index.json)
struct ToolIndex: Codable {
    let version: String
    let lastUpdated: Date?
    let tools: [ToolIndexEntry]?

    static let currentVersion = "1.0.0"
}

/// Entry in the tool index
struct ToolIndexEntry: Codable, Equatable {
    let id: String
    let path: String
    let category: ToolCategoryV2
    let enabled: Bool?
}

// MARK: - AnyCodableV2 Helper

/// Type-erased Codable wrapper for dynamic JSON values (V2 plugin system)
struct AnyCodableV2: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodableV2].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodableV2].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode AnyCodableV2 value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodableV2($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodableV2($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unable to encode AnyCodableV2 value"
                )
            )
        }
    }

    static func == (lhs: AnyCodableV2, rhs: AnyCodableV2) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (NSNull, NSNull):
            return true
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as String, r as String):
            return l == r
        case let (l as [Any], r as [Any]):
            return l.count == r.count && zip(l, r).allSatisfy { AnyCodableV2($0) == AnyCodableV2($1) }
        case let (l as [String: Any], r as [String: Any]):
            return l.count == r.count && l.keys.allSatisfy { key in
                guard let lVal = l[key], let rVal = r[key] else { return false }
                return AnyCodableV2(lVal) == AnyCodableV2(rVal)
            }
        default:
            return false
        }
    }
}

// MARK: - Validation

extension ToolManifest {
    /// Validates the manifest and returns any issues found
    func validate() -> [ToolManifestIssue] {
        var issues: [ToolManifestIssue] = []

        // Validate version
        if version.isEmpty {
            issues.append(.error("Version is required"))
        }

        // Validate tool definition
        if tool.id.isEmpty {
            issues.append(.error("Tool ID is required"))
        }
        if tool.name.isEmpty {
            issues.append(.error("Tool name is required"))
        }
        if tool.description.isEmpty {
            issues.append(.warning("Tool description is empty"))
        }

        // Validate execution
        switch execution.type {
        case .internalHandler:
            if execution.handler == nil || execution.handler?.isEmpty == true {
                issues.append(.error("Internal handler execution requires a handler name"))
            }
        case .pipeline:
            if execution.pipeline == nil || execution.pipeline?.isEmpty == true {
                issues.append(.error("Pipeline execution requires pipeline steps"))
            }
        case .providerNative:
            if execution.provider == nil || execution.provider?.isEmpty == true {
                issues.append(.error("Provider native execution requires a provider name"))
            }
        case .urlScheme:
            if execution.urlTemplate == nil || execution.urlTemplate?.isEmpty == true {
                issues.append(.error("URL scheme execution requires a URL template"))
            }
        case .shortcut:
            if execution.shortcutName == nil || execution.shortcutName?.isEmpty == true {
                issues.append(.error("Shortcut execution requires a shortcut name"))
            }
        case .bridge:
            if execution.bridgeMethod == nil || execution.bridgeMethod?.isEmpty == true {
                issues.append(.error("Bridge execution requires a bridgeMethod (e.g., 'system/info')"))
            }
        }

        // Validate parameters
        if let params = parameters {
            for (name, param) in params {
                if param.type == .enum && (param.enum == nil || param.enum?.isEmpty == true) {
                    issues.append(.error("Parameter '\(name)' is enum type but has no enum values"))
                }
            }
        }

        return issues
    }
}

/// Issue found during manifest validation
enum ToolManifestIssue: Equatable {
    case error(String)
    case warning(String)
    case info(String)

    var message: String {
        switch self {
        case .error(let msg), .warning(let msg), .info(let msg):
            return msg
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
