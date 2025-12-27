//
//  SoloAgenda.swift
//  Axon
//
//  Agenda items for solo thread sessions - tasks that Axon can work on autonomously.
//  Both users and Axon can add agenda items; users set explicit tasks while Axon can suggest.
//

import Foundation

// MARK: - Solo Agenda Item

/// A task that Axon can work on during solo thread sessions
struct SoloAgendaItem: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: String
    
    /// Description of the task to work on
    let task: String
    
    /// Priority (1 = highest)
    let priority: Int
    
    /// When this item was created
    let createdAt: Date
    
    /// Who created this item
    let createdBy: AgendaSource
    
    /// Current status of the item
    var status: AgendaStatus
    
    /// Optional notes about progress or outcome
    var progressNotes: String?
    
    /// ID of the solo thread that worked on this item (if any)
    var soloThreadId: String?
    
    /// When the item was completed (if applicable)
    var completedAt: Date?
    
    /// Tags for categorization
    var tags: [String]?
    
    /// Optional deadline
    var deadline: Date?
    
    // MARK: - Computed Properties
    
    /// Whether this item is actionable (not completed/deferred)
    var isActionable: Bool {
        switch status {
        case .pending, .inProgress:
            return true
        case .completed, .deferred, .cancelled:
            return false
        }
    }
    
    /// Whether the deadline has passed
    var isOverdue: Bool {
        guard let deadline = deadline else { return false }
        return status.isActionable && deadline < Date()
    }
}

// MARK: - Agenda Source

/// Who created an agenda item
enum AgendaSource: String, Codable, Sendable {
    /// User explicitly assigned this task
    case user
    
    /// Axon suggested this during internal thread reflection
    case axon
    
    /// System-generated (e.g., from a schedule)
    case system
    
    var displayName: String {
        switch self {
        case .user: return "User"
        case .axon: return "Axon"
        case .system: return "System"
        }
    }
    
    var icon: String {
        switch self {
        case .user: return "person.fill"
        case .axon: return "cpu"
        case .system: return "gearshape.fill"
        }
    }
}

// MARK: - Agenda Status

/// Current status of an agenda item
enum AgendaStatus: String, Codable, Sendable {
    /// Not yet started
    case pending
    
    /// Currently being worked on
    case inProgress
    
    /// Successfully completed
    case completed
    
    /// Postponed for later
    case deferred
    
    /// Cancelled (won't be worked on)
    case cancelled
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .deferred: return "Deferred"
        case .cancelled: return "Cancelled"
        }
    }
    
    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .deferred: return "clock.arrow.circlepath"
        case .cancelled: return "xmark.circle"
        }
    }
    
    /// Whether this status allows work to be done
    var isActionable: Bool {
        switch self {
        case .pending, .inProgress:
            return true
        case .completed, .deferred, .cancelled:
            return false
        }
    }
}

// MARK: - Solo Agenda

/// Collection of agenda items with helper methods
struct SoloAgenda: Codable, Equatable, Sendable {
    /// All agenda items
    var items: [SoloAgendaItem]
    
    // MARK: - Computed Properties
    
    /// Items that can be worked on, sorted by priority
    var actionableItems: [SoloAgendaItem] {
        items
            .filter { $0.isActionable }
            .sorted { $0.priority < $1.priority }
    }
    
    /// Next item to work on (highest priority actionable)
    var nextItem: SoloAgendaItem? {
        actionableItems.first
    }
    
    /// Items created by user
    var userItems: [SoloAgendaItem] {
        items.filter { $0.createdBy == .user }
    }
    
    /// Items suggested by Axon
    var axonSuggestions: [SoloAgendaItem] {
        items.filter { $0.createdBy == .axon }
    }
    
    /// Overdue items
    var overdueItems: [SoloAgendaItem] {
        items.filter { $0.isOverdue }
    }
    
    // MARK: - Mutating Methods
    
    /// Add a new agenda item
    mutating func add(_ item: SoloAgendaItem) {
        items.append(item)
    }
    
    /// Remove an item by ID
    mutating func remove(id: String) {
        items.removeAll { $0.id == id }
    }
    
    /// Update an item's status
    mutating func updateStatus(id: String, status: AgendaStatus) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].status = status
            if status == .completed {
                items[index].completedAt = Date()
            }
        }
    }
    
    /// Mark an item as being worked on by a solo thread
    mutating func startWorking(id: String, soloThreadId: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].status = .inProgress
            items[index].soloThreadId = soloThreadId
        }
    }
    
    /// Add progress notes to an item
    mutating func addNotes(id: String, notes: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            if let existing = items[index].progressNotes {
                items[index].progressNotes = existing + "\n" + notes
            } else {
                items[index].progressNotes = notes
            }
        }
    }
}

// MARK: - Factory Methods

extension SoloAgendaItem {
    /// Create a new user-assigned task
    static func userTask(
        task: String,
        priority: Int = 5,
        deadline: Date? = nil,
        tags: [String]? = nil
    ) -> SoloAgendaItem {
        SoloAgendaItem(
            id: UUID().uuidString,
            task: task,
            priority: priority,
            createdAt: Date(),
            createdBy: .user,
            status: .pending,
            progressNotes: nil,
            soloThreadId: nil,
            completedAt: nil,
            tags: tags,
            deadline: deadline
        )
    }
    
    /// Create a new Axon-suggested task
    static func axonSuggestion(
        task: String,
        priority: Int = 5,
        tags: [String]? = nil
    ) -> SoloAgendaItem {
        SoloAgendaItem(
            id: UUID().uuidString,
            task: task,
            priority: priority,
            createdAt: Date(),
            createdBy: .axon,
            status: .pending,
            progressNotes: nil,
            soloThreadId: nil,
            completedAt: nil,
            tags: tags,
            deadline: nil
        )
    }
}

extension SoloAgenda {
    /// Empty agenda
    static let empty = SoloAgenda(items: [])
}
