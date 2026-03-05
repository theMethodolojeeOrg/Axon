//
//  DynamicToolConfiguration.swift
//  Axon
//
//  JSON-based dynamic tool configuration types for user-defined and composite tools
//

import Foundation

// MARK: - Root Configuration

/// Root configuration containing all dynamic tools
struct DynamicToolCatalog: Codable, Equatable, Sendable {
    let version: String
    let lastUpdated: Date
    var tools: [DynamicToolConfig]

    enum CodingKeys: String, CodingKey {
        case version, lastUpdated, tools
    }

    init(version: String, lastUpdated: Date, tools: [DynamicToolConfig]) {
        self.version = version
        self.lastUpdated = lastUpdated
        self.tools = tools
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        tools = try container.decode([DynamicToolConfig].self, forKey: .tools)

        // Handle ISO8601 date string
        let dateString = try container.decode(String.self, forKey: .lastUpdated)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            lastUpdated = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                lastUpdated = date
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .lastUpdated,
                    in: container,
                    debugDescription: "Invalid date format: \(dateString)"
                )
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(tools, forKey: .tools)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        try container.encode(formatter.string(from: lastUpdated), forKey: .lastUpdated)
    }
}

// MARK: - Tool Configuration

/// Configuration for a single dynamic tool
struct DynamicToolConfig: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var description: String
    var category: DynamicToolCategory
    var enabled: Bool
    var icon: String
    var requiredSecrets: [String]
    var pipeline: [PipelineStep]
    var parameters: [String: ToolParameter]
    var outputTemplate: String?

    // MARK: - Biometric Approval

    /// Whether this tool requires biometric approval before execution
    var requiresApproval: Bool

    /// Human-readable descriptions of what this tool can access (shown in approval UI)
    /// Supports template variables like "Access repository: {{input.repo_source}}"
    var approvalScopes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, enabled, icon
        case requiredSecrets, pipeline, parameters, outputTemplate
        case requiresApproval, approvalScopes
    }

    init(
        id: String,
        name: String,
        description: String,
        category: DynamicToolCategory,
        enabled: Bool,
        icon: String,
        requiredSecrets: [String],
        pipeline: [PipelineStep],
        parameters: [String: ToolParameter],
        outputTemplate: String? = nil,
        requiresApproval: Bool = false,
        approvalScopes: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.enabled = enabled
        self.icon = icon
        self.requiredSecrets = requiredSecrets
        self.pipeline = pipeline
        self.parameters = parameters
        self.outputTemplate = outputTemplate
        self.requiresApproval = requiresApproval
        self.approvalScopes = approvalScopes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        category = try container.decode(DynamicToolCategory.self, forKey: .category)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        icon = try container.decode(String.self, forKey: .icon)
        requiredSecrets = try container.decode([String].self, forKey: .requiredSecrets)
        pipeline = try container.decode([PipelineStep].self, forKey: .pipeline)
        parameters = try container.decode([String: ToolParameter].self, forKey: .parameters)
        outputTemplate = try container.decodeIfPresent(String.self, forKey: .outputTemplate)
        // Default to false for backwards compatibility
        requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
        approvalScopes = try container.decodeIfPresent([String].self, forKey: .approvalScopes)
    }

    /// Generate the tool description for injection into system prompts
    func generatePromptDescription() -> String {
        var desc = "### \(id)\n\(description)\n"

        if !parameters.isEmpty {
            desc += "Parameters:\n"
            for (name, param) in parameters.sorted(by: { $0.key < $1.key }) {
                let required = param.required ? "(required)" : "(optional)"
                desc += "- \(name) \(required): \(param.description)\n"
            }
        }

        desc += """
        Example: ```tool_request
        {"tool": "\(id)", "query": "your parameters as JSON or pipe-separated values"}
        ```
        """

        return desc
    }
}

// MARK: - Tool Category

enum DynamicToolCategory: String, Codable, CaseIterable, Sendable {
    case integration   // External API integrations (Jules, Linear, etc.)
    case composite     // Multi-model pipelines
    case research      // Research/search tools
    case utility       // General utilities
    case custom        // User-created tools
}

// MARK: - Tool Parameter

struct ToolParameter: Codable, Equatable, Sendable {
    let type: ParameterType
    let required: Bool
    let description: String
    let defaultValue: String?

    enum CodingKeys: String, CodingKey {
        case type, required, description
        case defaultValue = "default"
    }

    init(type: ParameterType, required: Bool, description: String, defaultValue: String? = nil) {
        self.type = type
        self.required = required
        self.description = description
        self.defaultValue = defaultValue
    }
}

enum ParameterType: String, Codable, Sendable {
    case string
    case number
    case boolean
    case array
    case object
}

// MARK: - Pipeline Steps

/// A step in the tool execution pipeline
struct PipelineStep: Codable, Equatable, Sendable {
    let type: PipelineStepType
    let id: String
    let config: PipelineStepConfig?
    let condition: String?          // For conditional steps
    let then: [PipelineStep]?       // Steps to execute if condition is true
    let `else`: [PipelineStep]?     // Steps to execute if condition is false
    let steps: [PipelineStep]?      // For parallel execution

    enum CodingKeys: String, CodingKey {
        case type, id, config, condition, then, `else`, steps
    }

    init(
        type: PipelineStepType,
        id: String,
        config: PipelineStepConfig? = nil,
        condition: String? = nil,
        then: [PipelineStep]? = nil,
        `else`: [PipelineStep]? = nil,
        steps: [PipelineStep]? = nil
    ) {
        self.type = type
        self.id = id
        self.config = config
        self.condition = condition
        self.then = then
        self.else = `else`
        self.steps = steps
    }
}

enum PipelineStepType: String, Codable, Sendable {
    case modelCall = "model_call"
    case apiCall = "api_call"
    case transform = "transform"
    case conditional = "conditional"
    case parallel = "parallel"
    case loop = "loop"
}

// MARK: - Pipeline Step Configuration

struct PipelineStepConfig: Codable, Equatable, Sendable {
    // For model_call
    let provider: String?
    let model: String?
    let systemPrompt: String?
    let userPrompt: String?
    let responseFormat: String?

    // For api_call
    let method: String?
    let endpoint: String?
    let headers: [String: String]?
    let body: AnyCodable?

    // For transform
    let expression: String?

    // For loop
    let items: String?
    let itemVariable: String?

    enum CodingKeys: String, CodingKey {
        case provider, model, systemPrompt, userPrompt, responseFormat
        case method, endpoint, headers, body
        case expression
        case items, itemVariable
    }
}

// MARK: - AnyCodable Extensions

extension AnyCodable {
    /// Convert to dictionary for JSON serialization
    func toDictionary() -> [String: Any]? {
        return toAny() as? [String: Any]
    }

    /// Convert to Any value
    func toAny() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let array):
            return array.map { $0.toAny() }
        case .object(let dict):
            return dict.mapValues { $0.toAny() }
        }
    }
}

// MARK: - Pipeline Execution Context

/// Context passed through pipeline execution
struct PipelineExecutionContext: Sendable {
    var inputs: [String: Any]
    var stepOutputs: [String: Any]
    var secrets: [String: String]

    init(inputs: [String: Any] = [:], secrets: [String: String] = [:]) {
        self.inputs = inputs
        self.stepOutputs = [:]
        self.secrets = secrets
    }

    /// Resolve a template string like "{{input.topic}}" or "{{steps.research.output}}"
    func resolve(_ template: String) -> String {
        var result = template

        // Resolve input references: {{input.key}}
        let inputPattern = "\\{\\{input\\.([^}]+)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: inputPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let keyRange = Range(match.range(at: 1), in: result) {
                    let key = String(result[keyRange])
                    if let value = inputs[key] {
                        let fullRange = Range(match.range, in: result)!
                        result.replaceSubrange(fullRange, with: String(describing: value))
                    }
                }
            }
        }

        // Resolve step output references: {{steps.step_id.output}} or {{steps.step_id.output.key}}
        let stepsPattern = "\\{\\{steps\\.([^.]+)\\.output(?:\\.([^}]+))?\\}\\}"
        if let regex = try? NSRegularExpression(pattern: stepsPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let stepIdRange = Range(match.range(at: 1), in: result) {
                    let stepId = String(result[stepIdRange])
                    if let output = stepOutputs[stepId] {
                        var value: Any = output

                        // Check for nested key access
                        if match.numberOfRanges > 2,
                           let keyRange = Range(match.range(at: 2), in: result) {
                            let key = String(result[keyRange])
                            if let dict = output as? [String: Any], let nestedValue = dict[key] {
                                value = nestedValue
                            }
                        }

                        let fullRange = Range(match.range, in: result)!
                        if let stringValue = value as? String {
                            result.replaceSubrange(fullRange, with: stringValue)
                        } else if let data = try? JSONSerialization.data(withJSONObject: value),
                                  let jsonString = String(data: data, encoding: .utf8) {
                            result.replaceSubrange(fullRange, with: jsonString)
                        } else {
                            result.replaceSubrange(fullRange, with: String(describing: value))
                        }
                    }
                }
            }
        }

        // Resolve secret references: {{secrets.key}}
        let secretsPattern = "\\{\\{secrets\\.([^}]+)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: secretsPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let keyRange = Range(match.range(at: 1), in: result) {
                    let key = String(result[keyRange])
                    if let value = secrets[key] {
                        let fullRange = Range(match.range, in: result)!
                        result.replaceSubrange(fullRange, with: value)
                    }
                }
            }
        }

        return result
    }

    /// Resolve template in a dictionary (recursive)
    func resolveInDictionary(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                result[key] = resolve(stringValue)
            } else if let nestedDict = value as? [String: Any] {
                result[key] = resolveInDictionary(nestedDict)
            } else if let array = value as? [Any] {
                result[key] = array.map { item -> Any in
                    if let stringItem = item as? String {
                        return resolve(stringItem)
                    } else if let dictItem = item as? [String: Any] {
                        return resolveInDictionary(dictItem)
                    }
                    return item
                }
            } else {
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - Validation

extension DynamicToolCatalog {
    /// Validates the catalog structure and returns any issues found
    func validate() -> [DynamicToolIssue] {
        var issues: [DynamicToolIssue] = []

        // Check for duplicate tool IDs
        let toolIds = tools.map { $0.id }
        let duplicates = Dictionary(grouping: toolIds, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
        for id in duplicates {
            issues.append(.duplicateToolId(id))
        }

        // Validate each tool
        for tool in tools {
            // Check pipeline is not empty
            if tool.pipeline.isEmpty {
                issues.append(.emptyPipeline(toolId: tool.id))
            }

            // Validate required parameters have descriptions
            for (name, param) in tool.parameters where param.required && param.description.isEmpty {
                issues.append(.missingParameterDescription(toolId: tool.id, parameter: name))
            }

            // Validate pipeline steps
            for step in tool.pipeline {
                if let stepIssues = validateStep(step, toolId: tool.id) {
                    issues.append(contentsOf: stepIssues)
                }
            }
        }

        return issues
    }

    private func validateStep(_ step: PipelineStep, toolId: String) -> [DynamicToolIssue]? {
        var issues: [DynamicToolIssue] = []

        switch step.type {
        case .modelCall:
            if step.config?.provider == nil || step.config?.model == nil {
                issues.append(.invalidStepConfig(toolId: toolId, stepId: step.id, reason: "model_call requires provider and model"))
            }

        case .apiCall:
            if step.config?.method == nil || step.config?.endpoint == nil {
                issues.append(.invalidStepConfig(toolId: toolId, stepId: step.id, reason: "api_call requires method and endpoint"))
            }

        case .conditional:
            if step.condition == nil {
                issues.append(.invalidStepConfig(toolId: toolId, stepId: step.id, reason: "conditional requires condition"))
            }

        case .parallel:
            if step.steps == nil || step.steps?.isEmpty == true {
                issues.append(.invalidStepConfig(toolId: toolId, stepId: step.id, reason: "parallel requires steps array"))
            }

        default:
            break
        }

        // Recursively validate nested steps
        if let thenSteps = step.then {
            for nestedStep in thenSteps {
                if let nestedIssues = validateStep(nestedStep, toolId: toolId) {
                    issues.append(contentsOf: nestedIssues)
                }
            }
        }

        if let elseSteps = step.else {
            for nestedStep in elseSteps {
                if let nestedIssues = validateStep(nestedStep, toolId: toolId) {
                    issues.append(contentsOf: nestedIssues)
                }
            }
        }

        if let parallelSteps = step.steps {
            for nestedStep in parallelSteps {
                if let nestedIssues = validateStep(nestedStep, toolId: toolId) {
                    issues.append(contentsOf: nestedIssues)
                }
            }
        }

        return issues.isEmpty ? nil : issues
    }
}

enum DynamicToolIssue: Equatable, Sendable {
    case duplicateToolId(String)
    case emptyPipeline(toolId: String)
    case missingParameterDescription(toolId: String, parameter: String)
    case invalidStepConfig(toolId: String, stepId: String, reason: String)
    case parseError(String)

    var description: String {
        switch self {
        case .duplicateToolId(let id):
            return "Duplicate tool ID: \(id)"
        case .emptyPipeline(let toolId):
            return "Tool '\(toolId)' has an empty pipeline"
        case .missingParameterDescription(let toolId, let parameter):
            return "Parameter '\(parameter)' in tool '\(toolId)' is missing description"
        case .invalidStepConfig(let toolId, let stepId, let reason):
            return "Invalid step '\(stepId)' in tool '\(toolId)': \(reason)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
