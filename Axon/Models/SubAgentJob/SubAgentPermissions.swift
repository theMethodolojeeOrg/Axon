//
//  SubAgentPermissions.swift
//  Axon
//
//  Permission scoping for sub-agents.
//  Controls read/write access, available tools, memory scope, and resource limits.
//

import Foundation

// MARK: - Sub-Agent Permissions

/// Permission configuration for a sub-agent job.
/// Defines what the sub-agent can and cannot do within its scoped execution.
struct SubAgentPermissions: Codable, Equatable, Sendable {
    /// Whether the sub-agent can read data (files, memories, conversations)
    let canRead: Bool

    /// Whether the sub-agent can write/modify data
    let canWrite: Bool

    /// The specific tools this sub-agent is allowed to use
    let allowedTools: [ToolId]

    /// How memory should be injected into the sub-agent's context
    let memoryScope: MemoryInjectionScope

    /// Maximum token budget for the sub-agent's output (nil = unlimited)
    let maxTokenBudget: Int?

    /// Maximum duration in seconds before the job times out (nil = unlimited)
    let maxDurationSeconds: Int?

    // MARK: - Initialization

    init(
        canRead: Bool,
        canWrite: Bool,
        allowedTools: [ToolId],
        memoryScope: MemoryInjectionScope,
        maxTokenBudget: Int? = nil,
        maxDurationSeconds: Int? = nil
    ) {
        self.canRead = canRead
        self.canWrite = canWrite
        self.allowedTools = allowedTools
        self.memoryScope = memoryScope
        self.maxTokenBudget = maxTokenBudget
        self.maxDurationSeconds = maxDurationSeconds
    }

    // MARK: - Permission Checks

    /// Check if a specific tool is allowed
    func isToolAllowed(_ tool: ToolId) -> Bool {
        allowedTools.contains(tool)
    }

    /// Check if a write operation is allowed
    func canPerformWrite() -> Bool {
        canWrite
    }

    /// Get the effective timeout interval
    var timeoutInterval: TimeInterval? {
        maxDurationSeconds.map { TimeInterval($0) }
    }

    // MARK: - Display Helpers

    var permissionSummary: String {
        var parts: [String] = []
        if canRead { parts.append("read") }
        if canWrite { parts.append("write") }
        parts.append("\(allowedTools.count) tools")
        parts.append(memoryScope.displayName)
        return parts.joined(separator: ", ")
    }

    var restrictionWarnings: [String] {
        var warnings: [String] = []
        if !canWrite {
            warnings.append("Read-only mode: cannot modify files or create memories")
        }
        if memoryScope == .none {
            warnings.append("No memory access: operating without historical context")
        }
        if let budget = maxTokenBudget, budget < 4000 {
            warnings.append("Limited token budget: responses may be truncated")
        }
        if let timeout = maxDurationSeconds, timeout < 30 {
            warnings.append("Short timeout: complex tasks may not complete")
        }
        return warnings
    }
}

// MARK: - Memory Injection Scope

/// Determines how memory is injected into a sub-agent's context.
enum MemoryInjectionScope: String, Codable, CaseIterable, Identifiable, Sendable {
    /// No memory injection - the sub-agent operates with zero historical context
    case none

    /// Only inject memories that match the job's context injection tags
    case tagFiltered

    /// Inherit context from the parent job's silo (for chained sub-agents)
    case inherited

    /// Full memory access - all memories available to the main Axon
    case full

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No Memory"
        case .tagFiltered: return "Tag-Filtered"
        case .inherited: return "Inherited"
        case .full: return "Full Access"
        }
    }

    var description: String {
        switch self {
        case .none:
            return "No memories injected. Sub-agent operates with fresh context only."
        case .tagFiltered:
            return "Only memories matching specified tags are injected."
        case .inherited:
            return "Context from parent job's silo is injected."
        case .full:
            return "Full memory access like main Axon (use sparingly)."
        }
    }

    var icon: String {
        switch self {
        case .none: return "brain.slash"
        case .tagFiltered: return "tag"
        case .inherited: return "arrow.down.circle"
        case .full: return "brain"
        }
    }
}

// MARK: - Preset Permission Profiles

extension SubAgentPermissions {
    /// Minimal permissions for quick reconnaissance
    static let scoutDefault = SubAgentPermissions(
        canRead: true,
        canWrite: false,
        allowedTools: [.googleSearch, .urlContext, .fileSearch, .conversationSearch],
        memoryScope: .tagFiltered,
        maxTokenBudget: 8_000,
        maxDurationSeconds: 60
    )

    /// Standard permissions for task execution
    static let mechanicDefault = SubAgentPermissions(
        canRead: true,
        canWrite: true,
        allowedTools: ToolId.allCases.filter {
            $0 != .proposeCovenantChange && $0 != .changeSystemState
        },
        memoryScope: .inherited,
        maxTokenBudget: 32_000,
        maxDurationSeconds: 300
    )

    /// Read-only with full memory for meta-analysis
    static let designerDefault = SubAgentPermissions(
        canRead: true,
        canWrite: false,
        allowedTools: [.conversationSearch, .reflectOnConversation, .querySystemState, .queryCovenant],
        memoryScope: .full,
        maxTokenBudget: 16_000,
        maxDurationSeconds: 120
    )

    /// Ultra-restrictive for untrusted or experimental tasks
    static let sandboxed = SubAgentPermissions(
        canRead: true,
        canWrite: false,
        allowedTools: [],
        memoryScope: .none,
        maxTokenBudget: 4_000,
        maxDurationSeconds: 30
    )
}

// MARK: - Permission Builder

extension SubAgentPermissions {
    /// Create a modified copy with specific tools added
    func adding(tools: [ToolId]) -> SubAgentPermissions {
        SubAgentPermissions(
            canRead: canRead,
            canWrite: canWrite,
            allowedTools: Array(Set(allowedTools + tools)),
            memoryScope: memoryScope,
            maxTokenBudget: maxTokenBudget,
            maxDurationSeconds: maxDurationSeconds
        )
    }

    /// Create a modified copy with specific tools removed
    func removing(tools: [ToolId]) -> SubAgentPermissions {
        SubAgentPermissions(
            canRead: canRead,
            canWrite: canWrite,
            allowedTools: allowedTools.filter { !tools.contains($0) },
            memoryScope: memoryScope,
            maxTokenBudget: maxTokenBudget,
            maxDurationSeconds: maxDurationSeconds
        )
    }

    /// Create a modified copy with a different memory scope
    func with(memoryScope: MemoryInjectionScope) -> SubAgentPermissions {
        SubAgentPermissions(
            canRead: canRead,
            canWrite: canWrite,
            allowedTools: allowedTools,
            memoryScope: memoryScope,
            maxTokenBudget: maxTokenBudget,
            maxDurationSeconds: maxDurationSeconds
        )
    }

    /// Create a modified copy with extended timeout
    func with(timeoutSeconds: Int) -> SubAgentPermissions {
        SubAgentPermissions(
            canRead: canRead,
            canWrite: canWrite,
            allowedTools: allowedTools,
            memoryScope: memoryScope,
            maxTokenBudget: maxTokenBudget,
            maxDurationSeconds: timeoutSeconds
        )
    }
}
