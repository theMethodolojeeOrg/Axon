//
//  ConversationReflectionService.swift
//  Axon
//
//  Provides meta-analysis of conversations: model timeline, task distribution,
//  memory retrieval patterns, and topic pivot detection.
//
//  This enables both the AI and user to understand:
//  - Which models handled which messages
//  - What each substrate was best at
//  - Which memories were retrieved when
//  - Where the conversation "pivoted" (task switches, topic shifts)
//

import Foundation

// MARK: - Reflection Models

/// Complete reflection analysis of a conversation
struct ConversationReflection: Codable {
    let conversationId: String
    let analyzedAt: Date
    let messageCount: Int
    let timeline: ModelTimeline
    let taskDistribution: TaskDistribution
    let memoryUsage: MemoryUsageAnalysis
    let pivots: [ConversationPivot]
    let insights: [ReflectionInsight]
}

/// Timeline of which models handled which messages
struct ModelTimeline: Codable {
    let entries: [ModelTimelineEntry]
    let totalMessages: Int
    let modelBreakdown: [String: ModelStats]

    struct ModelTimelineEntry: Codable, Identifiable {
        let id: String  // message ID
        let index: Int
        let timestamp: Date
        let role: String
        let model: String?
        let provider: String?
        let tokenCount: Int?
        let hadToolCalls: Bool
        let hadMemoryOps: Bool
        let contentPreview: String  // First 100 chars
    }

    struct ModelStats: Codable {
        let messageCount: Int
        let totalTokens: Int
        let toolCallCount: Int
        let memoryOpCount: Int
        let averageResponseLength: Int
    }
}

/// Analysis of what types of tasks different models handled
struct TaskDistribution: Codable {
    let modelTasks: [String: [TaskCategory]]
    let taskTimeline: [TaskTimelineEntry]

    struct TaskTimelineEntry: Codable {
        let messageIndex: Int
        let category: TaskCategory
        let model: String?
        let confidence: Double
    }
}

/// Categories of tasks detected in messages
enum TaskCategory: String, Codable, CaseIterable {
    case coding = "coding"
    case explanation = "explanation"
    case debugging = "debugging"
    case planning = "planning"
    case research = "research"
    case creative = "creative"
    case conversation = "conversation"
    case toolUse = "tool_use"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .coding: return "Code Writing"
        case .explanation: return "Explanation"
        case .debugging: return "Debugging"
        case .planning: return "Planning"
        case .research: return "Research"
        case .creative: return "Creative Writing"
        case .conversation: return "General Chat"
        case .toolUse: return "Tool Usage"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .explanation: return "text.book.closed"
        case .debugging: return "ant"
        case .planning: return "list.bullet.clipboard"
        case .research: return "magnifyingglass"
        case .creative: return "paintbrush"
        case .conversation: return "bubble.left.and.bubble.right"
        case .toolUse: return "hammer"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Analysis of memory retrieval and creation patterns
struct MemoryUsageAnalysis: Codable {
    let memoriesRetrieved: [MemoryRetrievalEvent]
    let memoriesCreated: [MemoryCreationEvent]
    let retrievalByModel: [String: Int]
    let creationByModel: [String: Int]
    let mostUsedTags: [String: Int]

    struct MemoryRetrievalEvent: Codable {
        let messageIndex: Int
        let memoryId: String
        let memoryType: String
        let tags: [String]
        let model: String?
    }

    struct MemoryCreationEvent: Codable {
        let messageIndex: Int
        let memoryType: String
        let content: String
        let tags: [String]
        let confidence: Double
        let model: String?
        let success: Bool
    }
}

/// A detected pivot point in the conversation
struct ConversationPivot: Codable, Identifiable {
    let id: String
    let messageIndex: Int
    let timestamp: Date
    let pivotType: PivotType
    let fromTopic: String?
    let toTopic: String?
    let fromModel: String?
    let toModel: String?
    let confidence: Double
    let description: String

    enum PivotType: String, Codable {
        case topicShift = "topic_shift"
        case modelSwitch = "model_switch"
        case taskSwitch = "task_switch"
        case toolInvocation = "tool_invocation"
        case memoryRetrieval = "memory_retrieval"
    }
}

/// High-level insights from the reflection
struct ReflectionInsight: Codable, Identifiable {
    let id: String
    let category: InsightCategory
    let title: String
    let description: String
    let relevantMessageIndices: [Int]

    enum InsightCategory: String, Codable {
        case modelStrength = "model_strength"
        case handoffQuality = "handoff_quality"
        case memoryPattern = "memory_pattern"
        case suggestion = "suggestion"
    }
}

// MARK: - Reflection Service

@MainActor
class ConversationReflectionService {
    static let shared = ConversationReflectionService()

    private init() {}

    /// Generate a full reflection analysis for a conversation
    func reflect(
        on messages: [Message],
        conversationId: String,
        options: ReflectionOptions = ReflectionOptions()
    ) -> ConversationReflection {
        let timeline = buildTimeline(from: messages, options: options)
        let taskDistribution = analyzeTaskDistribution(from: messages, timeline: timeline)
        let memoryUsage = analyzeMemoryUsage(from: messages)
        let pivots = detectPivots(from: messages, timeline: timeline, taskDistribution: taskDistribution)
        let insights = generateInsights(
            timeline: timeline,
            taskDistribution: taskDistribution,
            memoryUsage: memoryUsage,
            pivots: pivots
        )

        return ConversationReflection(
            conversationId: conversationId,
            analyzedAt: Date(),
            messageCount: messages.count,
            timeline: timeline,
            taskDistribution: taskDistribution,
            memoryUsage: memoryUsage,
            pivots: pivots,
            insights: insights
        )
    }

    /// Generate a formatted text report from reflection data
    func formatReflection(_ reflection: ConversationReflection, options: ReflectionOptions) -> String {
        var output = ""

        // Header
        output += "# Conversation Reflection\n\n"
        output += "**Messages analyzed:** \(reflection.messageCount)\n"
        output += "**Analysis time:** \(formatTime(reflection.analyzedAt))\n\n"

        // Model Timeline
        if options.showModelTimeline {
            output += "## Model Timeline\n\n"

            if reflection.timeline.modelBreakdown.isEmpty {
                output += "_No model information available._\n\n"
            } else {
                output += "| Model | Messages | Tokens | Tool Calls | Memories |\n"
                output += "|-------|----------|--------|------------|----------|\n"

                for (model, stats) in reflection.timeline.modelBreakdown.sorted(by: { $0.value.messageCount > $1.value.messageCount }) {
                    output += "| \(model) | \(stats.messageCount) | \(stats.totalTokens) | \(stats.toolCallCount) | \(stats.memoryOpCount) |\n"
                }
                output += "\n"

                // Timeline visualization
                output += "### Message Flow\n\n"
                output += "```\n"
                for entry in reflection.timeline.entries.prefix(20) {
                    let modelLabel = entry.model ?? "unknown"
                    let roleIcon = entry.role == "user" ? "👤" : "🤖"
                    let toolIcon = entry.hadToolCalls ? "🔧" : ""
                    let memoryIcon = entry.hadMemoryOps ? "🧠" : ""
                    output += "\(roleIcon) [\(entry.index)] \(modelLabel) \(toolIcon)\(memoryIcon)\n"
                    output += "   └─ \(entry.contentPreview.prefix(60))...\n"
                }
                if reflection.timeline.entries.count > 20 {
                    output += "   ... and \(reflection.timeline.entries.count - 20) more messages\n"
                }
                output += "```\n\n"
            }
        }

        // Task Distribution
        if options.showTaskDistribution {
            output += "## Task Distribution\n\n"

            if reflection.taskDistribution.modelTasks.isEmpty {
                output += "_No task distribution data available._\n\n"
            } else {
                for (model, tasks) in reflection.taskDistribution.modelTasks {
                    let taskCounts = Dictionary(grouping: tasks, by: { $0 }).mapValues { $0.count }
                    let taskSummary = taskCounts
                        .sorted { $0.value > $1.value }
                        .map { "\($0.key.displayName): \($0.value)" }
                        .joined(separator: ", ")

                    output += "**\(model)**: \(taskSummary)\n"
                }
                output += "\n"
            }
        }

        // Memory Usage
        if options.showMemoryUsage {
            output += "## Memory Usage\n\n"

            if reflection.memoryUsage.memoriesCreated.isEmpty && reflection.memoryUsage.memoriesRetrieved.isEmpty {
                output += "_No memory operations in this conversation._\n\n"
            } else {
                if !reflection.memoryUsage.memoriesCreated.isEmpty {
                    output += "### Memories Created (\(reflection.memoryUsage.memoriesCreated.count))\n\n"
                    for event in reflection.memoryUsage.memoriesCreated {
                        let statusIcon = event.success ? "✅" : "❌"
                        output += "- \(statusIcon) **\(event.memoryType)** (msg #\(event.messageIndex)): \(event.content.prefix(50))...\n"
                        output += "  - Tags: \(event.tags.joined(separator: ", "))\n"
                        output += "  - Model: \(event.model ?? "unknown"), Confidence: \(Int(event.confidence * 100))%\n"
                    }
                    output += "\n"
                }

                if !reflection.memoryUsage.mostUsedTags.isEmpty {
                    output += "### Most Used Tags\n\n"
                    for (tag, count) in reflection.memoryUsage.mostUsedTags.sorted(by: { $0.value > $1.value }).prefix(10) {
                        output += "- `\(tag)`: \(count) uses\n"
                    }
                    output += "\n"
                }
            }
        }

        // Pivots
        if !reflection.pivots.isEmpty {
            output += "## Conversation Pivots (\(reflection.pivots.count))\n\n"

            for pivot in reflection.pivots {
                let pivotIcon: String
                switch pivot.pivotType {
                case .topicShift: pivotIcon = "🔀"
                case .modelSwitch: pivotIcon = "🔄"
                case .taskSwitch: pivotIcon = "📋"
                case .toolInvocation: pivotIcon = "🔧"
                case .memoryRetrieval: pivotIcon = "🧠"
                }
                output += "- \(pivotIcon) **Message #\(pivot.messageIndex)**: \(pivot.description)\n"
            }
            output += "\n"
        }

        // Insights
        if !reflection.insights.isEmpty {
            output += "## Insights\n\n"
            for insight in reflection.insights {
                output += "### \(insight.title)\n"
                output += "\(insight.description)\n\n"
            }
        }

        return output
    }

    // MARK: - Private Analysis Methods

    private func buildTimeline(from messages: [Message], options: ReflectionOptions) -> ModelTimeline {
        var entries: [ModelTimeline.ModelTimelineEntry] = []
        var modelStats: [String: (messages: Int, tokens: Int, tools: Int, memories: Int, totalLength: Int)] = [:]

        for (index, message) in messages.enumerated() {
            let model = message.modelName ?? "unknown"
            let tokenCount = message.tokens?.total ?? 0
            let hadToolCalls = !(message.toolCalls?.isEmpty ?? true)
            let hadMemoryOps = !(message.memoryOperations?.isEmpty ?? true)

            let entry = ModelTimeline.ModelTimelineEntry(
                id: message.id,
                index: index,
                timestamp: message.timestamp,
                role: message.role.rawValue,
                model: message.modelName,
                provider: message.providerName,
                tokenCount: tokenCount,
                hadToolCalls: hadToolCalls,
                hadMemoryOps: hadMemoryOps,
                contentPreview: String(message.content.prefix(100))
            )
            entries.append(entry)

            // Update stats for assistant messages
            if message.role == .assistant {
                var stats = modelStats[model] ?? (0, 0, 0, 0, 0)
                stats.messages += 1
                stats.tokens += tokenCount
                stats.tools += message.toolCalls?.count ?? 0
                stats.memories += message.memoryOperations?.count ?? 0
                stats.totalLength += message.content.count
                modelStats[model] = stats
            }
        }

        let breakdown = modelStats.mapValues { stats in
            ModelTimeline.ModelStats(
                messageCount: stats.messages,
                totalTokens: stats.tokens,
                toolCallCount: stats.tools,
                memoryOpCount: stats.memories,
                averageResponseLength: stats.messages > 0 ? stats.totalLength / stats.messages : 0
            )
        }

        return ModelTimeline(
            entries: entries,
            totalMessages: messages.count,
            modelBreakdown: breakdown
        )
    }

    private func analyzeTaskDistribution(from messages: [Message], timeline: ModelTimeline) -> TaskDistribution {
        var modelTasks: [String: [TaskCategory]] = [:]
        var taskTimeline: [TaskDistribution.TaskTimelineEntry] = []

        for (index, message) in messages.enumerated() {
            let category = categorizeTask(message: message)
            let model = message.modelName ?? "unknown"

            if message.role == .assistant {
                modelTasks[model, default: []].append(category)
            }

            taskTimeline.append(TaskDistribution.TaskTimelineEntry(
                messageIndex: index,
                category: category,
                model: message.modelName,
                confidence: 0.8  // Could be improved with ML
            ))
        }

        return TaskDistribution(modelTasks: modelTasks, taskTimeline: taskTimeline)
    }

    private func categorizeTask(message: Message) -> TaskCategory {
        let content = message.content.lowercased()

        // Tool use is explicit
        if !(message.toolCalls?.isEmpty ?? true) {
            return .toolUse
        }

        // Check for code blocks
        if content.contains("```") || content.contains("func ") || content.contains("class ") ||
           content.contains("def ") || content.contains("function ") {
            // Determine if it's debugging or coding
            if content.contains("error") || content.contains("bug") || content.contains("fix") ||
               content.contains("issue") || content.contains("problem") {
                return .debugging
            }
            return .coding
        }

        // Check for planning indicators
        if content.contains("plan") || content.contains("steps") || content.contains("first,") ||
           content.contains("1.") && content.contains("2.") {
            return .planning
        }

        // Check for research/search
        if content.contains("search") || content.contains("found") || content.contains("according to") ||
           content.contains("sources") {
            return .research
        }

        // Check for explanations
        if content.contains("because") || content.contains("this means") || content.contains("in other words") ||
           content.contains("essentially") || content.contains("the reason") {
            return .explanation
        }

        // Check for creative content
        if content.contains("story") || content.contains("poem") || content.contains("once upon") {
            return .creative
        }

        return .conversation
    }

    private func analyzeMemoryUsage(from messages: [Message]) -> MemoryUsageAnalysis {
        var retrievals: [MemoryUsageAnalysis.MemoryRetrievalEvent] = []
        var creations: [MemoryUsageAnalysis.MemoryCreationEvent] = []
        var retrievalByModel: [String: Int] = [:]
        var creationByModel: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]

        for (index, message) in messages.enumerated() {
            // Track memory creations
            if let memoryOps = message.memoryOperations {
                for op in memoryOps where op.operationType == .create {
                    let model = message.modelName ?? "unknown"

                    creations.append(MemoryUsageAnalysis.MemoryCreationEvent(
                        messageIndex: index,
                        memoryType: op.memoryType,
                        content: op.content,
                        tags: op.tags,
                        confidence: op.confidence,
                        model: model,
                        success: op.success
                    ))

                    creationByModel[model, default: 0] += 1

                    for tag in op.tags {
                        tagCounts[tag, default: 0] += 1
                    }
                }
            }

            // TODO: Track memory retrievals when we have that data
            // This would require changes to how memories are retrieved and stored
        }

        return MemoryUsageAnalysis(
            memoriesRetrieved: retrievals,
            memoriesCreated: creations,
            retrievalByModel: retrievalByModel,
            creationByModel: creationByModel,
            mostUsedTags: tagCounts
        )
    }

    private func detectPivots(
        from messages: [Message],
        timeline: ModelTimeline,
        taskDistribution: TaskDistribution
    ) -> [ConversationPivot] {
        var pivots: [ConversationPivot] = []

        var previousModel: String? = nil
        var previousTask: TaskCategory? = nil

        for (index, message) in messages.enumerated() {
            guard message.role == .assistant else { continue }

            let currentModel = message.modelName
            let currentTask = taskDistribution.taskTimeline.first { $0.messageIndex == index }?.category ?? .unknown

            // Detect model switch
            if let prev = previousModel, let curr = currentModel, prev != curr {
                pivots.append(ConversationPivot(
                    id: UUID().uuidString,
                    messageIndex: index,
                    timestamp: message.timestamp,
                    pivotType: .modelSwitch,
                    fromTopic: nil,
                    toTopic: nil,
                    fromModel: prev,
                    toModel: curr,
                    confidence: 1.0,
                    description: "Model switched from \(prev) to \(curr)"
                ))
            }

            // Detect task switch
            if let prev = previousTask, prev != currentTask && currentTask != .unknown {
                pivots.append(ConversationPivot(
                    id: UUID().uuidString,
                    messageIndex: index,
                    timestamp: message.timestamp,
                    pivotType: .taskSwitch,
                    fromTopic: prev.displayName,
                    toTopic: currentTask.displayName,
                    fromModel: previousModel,
                    toModel: currentModel,
                    confidence: 0.8,
                    description: "Task shifted from \(prev.displayName) to \(currentTask.displayName)"
                ))
            }

            // Detect tool invocation pivot
            if !(message.toolCalls?.isEmpty ?? true) {
                for toolCall in message.toolCalls ?? [] {
                    pivots.append(ConversationPivot(
                        id: UUID().uuidString,
                        messageIndex: index,
                        timestamp: message.timestamp,
                        pivotType: .toolInvocation,
                        fromTopic: nil,
                        toTopic: toolCall.name,
                        fromModel: nil,
                        toModel: currentModel,
                        confidence: 1.0,
                        description: "Tool invoked: \(toolCall.name)"
                    ))
                }
            }

            // Detect memory operation pivot
            if !(message.memoryOperations?.isEmpty ?? true) {
                pivots.append(ConversationPivot(
                    id: UUID().uuidString,
                    messageIndex: index,
                    timestamp: message.timestamp,
                    pivotType: .memoryRetrieval,
                    fromTopic: nil,
                    toTopic: nil,
                    fromModel: nil,
                    toModel: currentModel,
                    confidence: 1.0,
                    description: "Memory operation performed (\(message.memoryOperations?.count ?? 0) ops)"
                ))
            }

            previousModel = currentModel
            previousTask = currentTask
        }

        return pivots
    }

    private func generateInsights(
        timeline: ModelTimeline,
        taskDistribution: TaskDistribution,
        memoryUsage: MemoryUsageAnalysis,
        pivots: [ConversationPivot]
    ) -> [ReflectionInsight] {
        var insights: [ReflectionInsight] = []

        // Model strength insights
        for (model, tasks) in taskDistribution.modelTasks {
            let taskCounts = Dictionary(grouping: tasks, by: { $0 }).mapValues { $0.count }
            if let topTask = taskCounts.max(by: { $0.value < $1.value }) {
                if topTask.value >= 3 {
                    insights.append(ReflectionInsight(
                        id: UUID().uuidString,
                        category: .modelStrength,
                        title: "\(model) excels at \(topTask.key.displayName)",
                        description: "\(model) handled \(topTask.value) \(topTask.key.displayName.lowercased()) tasks in this conversation.",
                        relevantMessageIndices: []
                    ))
                }
            }
        }

        // Handoff quality insights
        let modelSwitches = pivots.filter { $0.pivotType == .modelSwitch }
        if modelSwitches.count > 2 {
            insights.append(ReflectionInsight(
                id: UUID().uuidString,
                category: .handoffQuality,
                title: "Multiple model handoffs detected",
                description: "This conversation had \(modelSwitches.count) model switches. Consider if routing is optimal.",
                relevantMessageIndices: modelSwitches.map { $0.messageIndex }
            ))
        }

        // Memory pattern insights
        if memoryUsage.memoriesCreated.count > 3 {
            let successRate = Double(memoryUsage.memoriesCreated.filter { $0.success }.count) / Double(memoryUsage.memoriesCreated.count)
            insights.append(ReflectionInsight(
                id: UUID().uuidString,
                category: .memoryPattern,
                title: "Active memory creation",
                description: "\(memoryUsage.memoriesCreated.count) memories created with \(Int(successRate * 100))% success rate.",
                relevantMessageIndices: memoryUsage.memoriesCreated.map { $0.messageIndex }
            ))
        }

        return insights
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Options

struct ReflectionOptions: Codable {
    var showModelTimeline: Bool = true
    var showTaskDistribution: Bool = true
    var showMemoryUsage: Bool = true
    var showPivots: Bool = true
    var showInsights: Bool = true

    init(
        showModelTimeline: Bool = true,
        showTaskDistribution: Bool = true,
        showMemoryUsage: Bool = true,
        showPivots: Bool = true,
        showInsights: Bool = true
    ) {
        self.showModelTimeline = showModelTimeline
        self.showTaskDistribution = showTaskDistribution
        self.showMemoryUsage = showMemoryUsage
        self.showPivots = showPivots
        self.showInsights = showInsights
    }
}
