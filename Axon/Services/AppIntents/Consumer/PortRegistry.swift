//
//  PortRegistry.swift
//  Axon
//
//  Registry of external app capabilities that Axon can invoke.
//  Includes curated catalog and user-imported shortcuts.
//
#if canImport(UIKit)
  import UIKit
  #endif
  #if canImport(AppKit)
  import AppKit
  #endif
import Foundation
import SwiftUI
import Combine
import os.log

// MARK: - Port Registry

@MainActor
final class PortRegistry: ObservableObject {
    static let shared = PortRegistry()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "PortRegistry")

    // MARK: - Published State

    /// All available ports (built-in + user-added)
    @Published private(set) var ports: [PortRegistryEntry] = []

    /// User-imported shortcuts
    @Published private(set) var importedShortcuts: [ImportedShortcut] = []

    /// Whether the registry has been loaded
    @Published private(set) var isLoaded = false

    // MARK: - Storage Keys

    private let userPortsKey = "user_ports"
    private let importedShortcutsKey = "imported_shortcuts"
    private let disabledBuiltInPortsKey = "disabled_builtin_ports"

    // MARK: - Initialization

    private init() {
        loadRegistry()
    }

    // MARK: - Public API

    /// Get all enabled ports (for AI tool discovery)
    var enabledPorts: [PortRegistryEntry] {
        ports.filter { $0.isEnabled }
    }

    /// Get ports by category
    func ports(in category: PortCategory) -> [PortRegistryEntry] {
        ports.filter { $0.category == category && $0.isEnabled }
    }

    /// Get a specific port by ID
    func port(id: String) -> PortRegistryEntry? {
        ports.first { $0.id == id }
    }

    /// Search ports by query
    func searchPorts(query: String) -> [PortRegistryEntry] {
        guard !query.isEmpty else { return enabledPorts }

        let lowercasedQuery = query.lowercased()
        return enabledPorts.filter { port in
            port.name.lowercased().contains(lowercasedQuery) ||
            port.description.lowercased().contains(lowercasedQuery) ||
            port.appName.lowercased().contains(lowercasedQuery)
        }
    }

    /// Check if an app is installed (by URL scheme)
    func isAppInstalled(scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        #if canImport(UIKit)
        return UIApplication.shared.canOpenURL(url)
        #elseif canImport(AppKit)
        // On macOS, check if any app can open the URL using NSWorkspace
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        #else
        return false
        #endif
    }

    /// Toggle a built-in port's enabled state
    func togglePort(id: String, enabled: Bool) {
        if let index = ports.firstIndex(where: { $0.id == id }) {
            ports[index].isEnabled = enabled

            // Persist disabled state for built-in ports
            if ports[index].isBuiltIn {
                var disabled = loadDisabledBuiltInPorts()
                if enabled {
                    disabled.remove(id)
                } else {
                    disabled.insert(id)
                }
                saveDisabledBuiltInPorts(disabled)
            } else {
                // Save user ports
                saveUserPorts()
            }

            logger.info("Port '\(id)' \(enabled ? "enabled" : "disabled")")
        }
    }

    // MARK: - User-Added Ports

    /// Add a custom port
    func addUserPort(_ port: PortRegistryEntry) {
        var newPort = port
        newPort.isBuiltIn = false
        ports.append(newPort)
        saveUserPorts()
        logger.info("Added user port: \(port.id)")
    }

    /// Remove a user-added port
    func removeUserPort(id: String) {
        ports.removeAll { $0.id == id && !$0.isBuiltIn }
        saveUserPorts()
        logger.info("Removed user port: \(id)")
    }

    /// Update a user-added port
    func updateUserPort(_ port: PortRegistryEntry) {
        guard !port.isBuiltIn else {
            logger.warning("Cannot update built-in port: \(port.id)")
            return
        }

        if let index = ports.firstIndex(where: { $0.id == port.id }) {
            ports[index] = port
            saveUserPorts()
            logger.info("Updated user port: \(port.id)")
        }
    }

    // MARK: - Imported Shortcuts

    /// Import a shortcut by name
    func importShortcut(name: String, description: String = "", inputDescription: String? = nil) {
        let shortcut = ImportedShortcut(
            name: name,
            description: description,
            inputDescription: inputDescription
        )
        importedShortcuts.append(shortcut)
        saveImportedShortcuts()

        // Also add as a port for unified handling
        ports.append(shortcut.toPortEntry())

        logger.info("Imported shortcut: \(name)")
    }

    /// Remove an imported shortcut
    func removeShortcut(id: String) {
        importedShortcuts.removeAll { $0.id == id }
        ports.removeAll { $0.id == "shortcut_\(id)" }
        saveImportedShortcuts()
        logger.info("Removed shortcut: \(id)")
    }

    /// Toggle a shortcut's enabled state
    func toggleShortcut(id: String, enabled: Bool) {
        if let index = importedShortcuts.firstIndex(where: { $0.id == id }) {
            importedShortcuts[index].isEnabled = enabled
            saveImportedShortcuts()

            // Also update in ports array
            let portId = "shortcut_\(id)"
            if let portIndex = ports.firstIndex(where: { $0.id == portId }) {
                ports[portIndex].isEnabled = enabled
            }
        }
    }

    // MARK: - Registry Loading

    private func loadRegistry() {
        // 1. Load built-in catalog
        var allPorts = Self.curatedCatalog

        // 2. Apply disabled state to built-in ports
        let disabledIds = loadDisabledBuiltInPorts()
        for i in allPorts.indices {
            if disabledIds.contains(allPorts[i].id) {
                allPorts[i].isEnabled = false
            }
        }

        // 3. Load user-added ports
        let userPorts = loadUserPorts()
        allPorts.append(contentsOf: userPorts)

        // 4. Load imported shortcuts as ports
        let loadedShortcuts = loadImportedShortcuts()
        self.importedShortcuts = loadedShortcuts
        for shortcut in loadedShortcuts {
            allPorts.append(shortcut.toPortEntry())
        }

        ports = allPorts
        isLoaded = true

        logger.info("Loaded \(allPorts.count) ports (\(Self.curatedCatalog.count) built-in, \(userPorts.count) user, \(loadedShortcuts.count) shortcuts)")
    }

    // MARK: - Persistence

    private func saveUserPorts() {
        let userPorts = ports.filter { !$0.isBuiltIn }
        do {
            let data = try JSONEncoder().encode(userPorts)
            UserDefaults.standard.set(data, forKey: userPortsKey)
        } catch {
            logger.error("Failed to save user ports: \(error.localizedDescription)")
        }
    }

    private func loadUserPorts() -> [PortRegistryEntry] {
        guard let data = UserDefaults.standard.data(forKey: userPortsKey) else { return [] }
        do {
            return try JSONDecoder().decode([PortRegistryEntry].self, from: data)
        } catch {
            logger.error("Failed to load user ports: \(error.localizedDescription)")
            return []
        }
    }

    private func saveImportedShortcuts() {
        do {
            let data = try JSONEncoder().encode(importedShortcuts)
            UserDefaults.standard.set(data, forKey: importedShortcutsKey)
        } catch {
            logger.error("Failed to save imported shortcuts: \(error.localizedDescription)")
        }
    }

    private func loadImportedShortcuts() -> [ImportedShortcut] {
        guard let data = UserDefaults.standard.data(forKey: importedShortcutsKey) else { return [] }
        do {
            return try JSONDecoder().decode([ImportedShortcut].self, from: data)
        } catch {
            logger.error("Failed to load imported shortcuts: \(error.localizedDescription)")
            return []
        }
    }

    private func saveDisabledBuiltInPorts(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: disabledBuiltInPortsKey)
    }

    private func loadDisabledBuiltInPorts() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: disabledBuiltInPortsKey) ?? []
        return Set(array)
    }

    /// Generate system prompt injection for AI with all enabled ports
    func generateSystemPromptInjection() -> String {
        let enabled = enabledPorts
        guard !enabled.isEmpty else { return "" }

        var prompt = """
        ## Available External App Ports

        You can invoke the following external apps using the `invoke_port` tool:

        """

        // Group by category
        let grouped = Dictionary(grouping: enabled) { $0.category }
        for category in PortCategory.allCases {
            guard let categoryPorts = grouped[category], !categoryPorts.isEmpty else { continue }

            prompt += "\n### \(category.displayName)\n\n"
            for port in categoryPorts {
                prompt += port.generatePromptDescription()
                prompt += "\n"
            }
        }

        prompt += """

        To invoke a port, use:
        ```tool_request
        {"tool": "invoke_port", "query": "port_id | param1=value1 | param2=value2"}
        ```

        """

        return prompt
    }
}

// MARK: - Curated Catalog

extension PortRegistry {
    /// Built-in catalog of popular apps
    static let curatedCatalog: [PortRegistryEntry] = [
        // MARK: Notes & Writing

        PortRegistryEntry(
            id: "obsidian_new_note",
            name: "Create Obsidian Note",
            description: "Create a new note in Obsidian with a title and content",
            appName: "Obsidian",
            icon: "doc.text",
            category: .notes,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "name", description: "Note title/filename", isRequired: true, placeholder: "My Note"),
                PortParameter(name: "content", description: "Note content in markdown", type: .text, isRequired: false),
                PortParameter(name: "vault", description: "Vault name (optional)", isRequired: false)
            ],
            urlTemplate: "obsidian://new?name={{name}}&content={{content}}&vault={{vault}}",
            appStoreUrl: "https://apps.apple.com/app/obsidian-connected-notes/id1557175442",
            appScheme: "obsidian"
        ),

        PortRegistryEntry(
            id: "obsidian_open_note",
            name: "Open Obsidian Note",
            description: "Open an existing note in Obsidian",
            appName: "Obsidian",
            icon: "doc.text.magnifyingglass",
            category: .notes,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "file", description: "Path to the note file", isRequired: true, placeholder: "folder/note.md"),
                PortParameter(name: "vault", description: "Vault name (optional)", isRequired: false)
            ],
            urlTemplate: "obsidian://open?file={{file}}&vault={{vault}}",
            appStoreUrl: "https://apps.apple.com/app/obsidian-connected-notes/id1557175442",
            appScheme: "obsidian"
        ),

        PortRegistryEntry(
            id: "obsidian_search",
            name: "Search Obsidian",
            description: "Search for content across your Obsidian vault",
            appName: "Obsidian",
            icon: "magnifyingglass",
            category: .notes,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "query", description: "Search query", isRequired: true),
                PortParameter(name: "vault", description: "Vault name (optional)", isRequired: false)
            ],
            urlTemplate: "obsidian://search?query={{query}}&vault={{vault}}",
            appStoreUrl: "https://apps.apple.com/app/obsidian-connected-notes/id1557175442",
            appScheme: "obsidian"
        ),

        PortRegistryEntry(
            id: "bear_create",
            name: "Create Bear Note",
            description: "Create a new note in Bear",
            appName: "Bear",
            icon: "doc.text.fill",
            category: .notes,
            invocationType: .xCallbackUrl,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "title", description: "Note title", isRequired: false),
                PortParameter(name: "text", description: "Note content in markdown", type: .text, isRequired: true),
                PortParameter(name: "tags", description: "Comma-separated tags", isRequired: false)
            ],
            urlTemplate: "bear://x-callback-url/create?title={{title}}&text={{text}}&tags={{tags}}",
            appStoreUrl: "https://apps.apple.com/app/bear/id1016366447",
            appScheme: "bear"
        ),

        PortRegistryEntry(
            id: "bear_search",
            name: "Search Bear",
            description: "Search notes in Bear",
            appName: "Bear",
            icon: "magnifyingglass",
            category: .notes,
            invocationType: .xCallbackUrl,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "term", description: "Search term", isRequired: true),
                PortParameter(name: "tag", description: "Filter by tag", isRequired: false)
            ],
            urlTemplate: "bear://x-callback-url/search?term={{term}}&tag={{tag}}",
            appStoreUrl: "https://apps.apple.com/app/bear/id1016366447",
            appScheme: "bear"
        ),

        PortRegistryEntry(
            id: "drafts_create",
            name: "Create Draft",
            description: "Create a new draft in Drafts",
            appName: "Drafts",
            icon: "doc.badge.plus",
            category: .notes,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "text", description: "Draft content", type: .text, isRequired: true),
                PortParameter(name: "tag", description: "Tag to apply", isRequired: false)
            ],
            urlTemplate: "drafts://x-callback-url/create?text={{text}}&tag={{tag}}",
            appStoreUrl: "https://apps.apple.com/app/drafts/id1435957248",
            appScheme: "drafts"
        ),

        PortRegistryEntry(
            id: "apple_notes_create",
            name: "Create Apple Note",
            description: "Create a new note in Apple Notes",
            appName: "Notes",
            icon: "note.text",
            category: .notes,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "text", description: "Note content", type: .text, isRequired: true)
            ],
            urlTemplate: "mobilenotes://x-callback-url/create?text={{text}}",
            appStoreUrl: nil,
            appScheme: "mobilenotes"
        ),

        // MARK: Tasks & Reminders

        PortRegistryEntry(
            id: "things_add",
            name: "Add Things Todo",
            description: "Create a new todo in Things 3",
            appName: "Things",
            icon: "checkmark.circle",
            category: .tasks,
            invocationType: .xCallbackUrl,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "title", description: "Todo title", isRequired: true),
                PortParameter(name: "notes", description: "Additional notes", type: .text, isRequired: false),
                PortParameter(name: "when", description: "When to do (today, tomorrow, evening, anytime, someday, or date)", isRequired: false),
                PortParameter(name: "deadline", description: "Deadline date (YYYY-MM-DD)", isRequired: false),
                PortParameter(name: "tags", description: "Comma-separated tags", isRequired: false),
                PortParameter(name: "list", description: "Project or area name", isRequired: false)
            ],
            urlTemplate: "things:///add?title={{title}}&notes={{notes}}&when={{when}}&deadline={{deadline}}&tags={{tags}}&list={{list}}",
            appStoreUrl: "https://apps.apple.com/app/things-3/id904237743",
            appScheme: "things"
        ),

        PortRegistryEntry(
            id: "things_show_list",
            name: "Show Things List",
            description: "Open a specific list in Things",
            appName: "Things",
            icon: "list.bullet",
            category: .tasks,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "id", description: "List ID (inbox, today, upcoming, anytime, someday, logbook)", isRequired: true)
            ],
            urlTemplate: "things:///show?id={{id}}",
            appStoreUrl: "https://apps.apple.com/app/things-3/id904237743",
            appScheme: "things"
        ),

        PortRegistryEntry(
            id: "todoist_add",
            name: "Add Todoist Task",
            description: "Create a new task in Todoist",
            appName: "Todoist",
            icon: "checkmark.circle.fill",
            category: .tasks,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "content", description: "Task content with natural language date support", isRequired: true),
                PortParameter(name: "project", description: "Project name", isRequired: false),
                PortParameter(name: "labels", description: "Comma-separated labels", isRequired: false),
                PortParameter(name: "priority", description: "Priority (1-4, 1 is highest)", isRequired: false)
            ],
            urlTemplate: "todoist://addtask?content={{content}}&project={{project}}&labels={{labels}}&priority={{priority}}",
            appStoreUrl: "https://apps.apple.com/app/todoist-to-do-list-planner/id585829637",
            appScheme: "todoist"
        ),

        PortRegistryEntry(
            id: "reminders_create",
            name: "Create Reminder",
            description: "Create a reminder in Apple Reminders",
            appName: "Reminders",
            icon: "list.bullet.clipboard",
            category: .tasks,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "title", description: "Reminder title", isRequired: true),
                PortParameter(name: "list", description: "List name", isRequired: false)
            ],
            urlTemplate: "x-apple-reminderkit://REMCDReminder/{{title}}",
            appStoreUrl: nil,
            appScheme: "x-apple-reminderkit"
        ),

        PortRegistryEntry(
            id: "omnifocus_add",
            name: "Add OmniFocus Task",
            description: "Create a new task in OmniFocus",
            appName: "OmniFocus",
            icon: "checkmark.seal",
            category: .tasks,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "name", description: "Task name", isRequired: true),
                PortParameter(name: "note", description: "Task notes", type: .text, isRequired: false),
                PortParameter(name: "project", description: "Project name", isRequired: false),
                PortParameter(name: "due", description: "Due date", isRequired: false)
            ],
            urlTemplate: "omnifocus:///add?name={{name}}&note={{note}}&project={{project}}&due={{due}}",
            appStoreUrl: "https://apps.apple.com/app/omnifocus-3/id1346190318",
            appScheme: "omnifocus"
        ),

        // MARK: Calendar

        PortRegistryEntry(
            id: "fantastical_add",
            name: "Add Fantastical Event",
            description: "Create an event in Fantastical using natural language",
            appName: "Fantastical",
            icon: "calendar.badge.plus",
            category: .calendar,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "sentence", description: "Natural language event description (e.g., 'Meeting tomorrow at 3pm')", isRequired: true),
                PortParameter(name: "notes", description: "Event notes", type: .text, isRequired: false)
            ],
            urlTemplate: "fantastical://parse?sentence={{sentence}}&notes={{notes}}&add=1",
            appStoreUrl: "https://apps.apple.com/app/fantastical-calendar-tasks/id718043190",
            appScheme: "fantastical"
        ),

        PortRegistryEntry(
            id: "calendar_new",
            name: "New Calendar Event",
            description: "Create a new event in Apple Calendar",
            appName: "Calendar",
            icon: "calendar",
            category: .calendar,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "title", description: "Event title", isRequired: true),
                PortParameter(name: "start", description: "Start date/time (ISO format)", isRequired: false),
                PortParameter(name: "end", description: "End date/time (ISO format)", isRequired: false)
            ],
            urlTemplate: "calshow://new?title={{title}}&start={{start}}&end={{end}}",
            appStoreUrl: nil,
            appScheme: "calshow"
        ),

        // MARK: Automation

        PortRegistryEntry(
            id: "shortcuts_run",
            name: "Run Shortcut",
            description: "Run an Apple Shortcut by name",
            appName: "Shortcuts",
            icon: "bolt.square.fill",
            category: .automation,
            invocationType: .shortcut,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "name", description: "Shortcut name", isRequired: true),
                PortParameter(name: "input", description: "Input text to pass to the shortcut", type: .text, isRequired: false)
            ],
            urlTemplate: "shortcuts://run-shortcut?name={{name}}&input=text&text={{input}}",
            appStoreUrl: nil,
            appScheme: "shortcuts"
        ),

        // MARK: Communication

        PortRegistryEntry(
            id: "mail_compose",
            name: "Compose Email",
            description: "Compose a new email",
            appName: "Mail",
            icon: "envelope",
            category: .communication,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "to", description: "Recipient email address", isRequired: false),
                PortParameter(name: "subject", description: "Email subject", isRequired: false),
                PortParameter(name: "body", description: "Email body", type: .text, isRequired: false),
                PortParameter(name: "cc", description: "CC recipients", isRequired: false)
            ],
            urlTemplate: "mailto:{{to}}?subject={{subject}}&body={{body}}&cc={{cc}}",
            appStoreUrl: nil,
            appScheme: "mailto"
        ),

        PortRegistryEntry(
            id: "messages_send",
            name: "Open Messages",
            description: "Open Messages to send a text",
            appName: "Messages",
            icon: "message",
            category: .communication,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "phone", description: "Phone number or email", isRequired: false),
                PortParameter(name: "body", description: "Message text", type: .text, isRequired: false)
            ],
            urlTemplate: "sms:{{phone}}&body={{body}}",
            appStoreUrl: nil,
            appScheme: "sms"
        ),

        // MARK: Browser

        PortRegistryEntry(
            id: "safari_open",
            name: "Open in Safari",
            description: "Open a URL in Safari",
            appName: "Safari",
            icon: "safari",
            category: .browser,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "url", description: "URL to open", type: .url, isRequired: true)
            ],
            urlTemplate: "{{url}}",
            appStoreUrl: nil,
            appScheme: nil
        ),

        PortRegistryEntry(
            id: "safari_reading_list",
            name: "Add to Reading List",
            description: "Add a URL to Safari Reading List",
            appName: "Safari",
            icon: "eyeglasses",
            category: .browser,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "url", description: "URL to save", type: .url, isRequired: true)
            ],
            urlTemplate: "x-safari-https://{{url}}",
            appStoreUrl: nil,
            appScheme: "x-safari-https"
        ),

        // MARK: Media

        PortRegistryEntry(
            id: "music_search",
            name: "Search Apple Music",
            description: "Search for music in Apple Music",
            appName: "Music",
            icon: "music.note",
            category: .media,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "term", description: "Search term", isRequired: true)
            ],
            urlTemplate: "music://search?term={{term}}",
            appStoreUrl: nil,
            appScheme: "music"
        ),

        PortRegistryEntry(
            id: "podcasts_search",
            name: "Search Podcasts",
            description: "Search for podcasts in Apple Podcasts",
            appName: "Podcasts",
            icon: "mic.fill",
            category: .media,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "term", description: "Search term", isRequired: true)
            ],
            urlTemplate: "podcasts://search?term={{term}}",
            appStoreUrl: nil,
            appScheme: "podcasts"
        ),

        // MARK: Developer

        PortRegistryEntry(
            id: "github_repo",
            name: "Open GitHub Repo",
            description: "Open a GitHub repository",
            appName: "GitHub",
            icon: "chevron.left.forwardslash.chevron.right",
            category: .developer,
            invocationType: .universal,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "owner", description: "Repository owner", isRequired: true),
                PortParameter(name: "repo", description: "Repository name", isRequired: true)
            ],
            urlTemplate: "https://github.com/{{owner}}/{{repo}}",
            appStoreUrl: "https://apps.apple.com/app/github/id1477376905",
            appScheme: "github"
        ),

        // MARK: Maps & Navigation

        PortRegistryEntry(
            id: "maps_directions",
            name: "Get Directions",
            description: "Get directions in Apple Maps",
            appName: "Maps",
            icon: "map",
            category: .custom,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "daddr", description: "Destination address", isRequired: true),
                PortParameter(name: "saddr", description: "Starting address (optional, defaults to current location)", isRequired: false)
            ],
            urlTemplate: "maps://?daddr={{daddr}}&saddr={{saddr}}",
            appStoreUrl: nil,
            appScheme: "maps"
        ),

        PortRegistryEntry(
            id: "maps_search",
            name: "Search Maps",
            description: "Search for a place in Apple Maps",
            appName: "Maps",
            icon: "location.magnifyingglass",
            category: .custom,
            invocationType: .urlScheme,
            isEnabled: true,
            isBuiltIn: true,
            parameters: [
                PortParameter(name: "q", description: "Search query", isRequired: true)
            ],
            urlTemplate: "maps://?q={{q}}",
            appStoreUrl: nil,
            appScheme: "maps"
        ),
    ]
}
