//
//  PortRegistryEntry.swift
//  Axon
//
//  Model for external app capabilities that Axon can invoke.
//  Supports URL schemes, x-callback-url, and Shortcuts invocation.
//

import Foundation

// MARK: - Port Registry Entry

/// Represents an external app capability that Axon can invoke
struct PortRegistryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var description: String
    var appName: String
    var icon: String  // SF Symbol name
    var category: PortCategory
    var invocationType: PortInvocationType
    var isEnabled: Bool
    var isBuiltIn: Bool  // Curated vs user-added

    // Parameters this port accepts
    var parameters: [PortParameter]

    // URL template with placeholders like {{title}}, {{content}}
    var urlTemplate: String

    // Optional: App Store URL for installation prompt
    var appStoreUrl: String?

    // Optional: URL scheme to check if app is installed
    var appScheme: String?

    /// Generate the invocation URL with provided parameter values
    func generateUrl(with values: [String: String]) -> URL? {
        var urlString = urlTemplate

        // Replace all placeholders
        for (key, value) in values {
            // URL encode the value
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            urlString = urlString.replacingOccurrences(of: "{{\(key)}}", with: encodedValue)
        }

        // Remove any unreplaced optional placeholders
        let optionalPattern = "\\{\\{[^}]+\\}\\}"
        if let regex = try? NSRegularExpression(pattern: optionalPattern) {
            urlString = regex.stringByReplacingMatches(
                in: urlString,
                range: NSRange(urlString.startIndex..., in: urlString),
                withTemplate: ""
            )
        }

        // Clean up any trailing ? or & from removed optional params
        urlString = urlString.trimmingCharacters(in: CharacterSet(charactersIn: "?&"))
        if urlString.hasSuffix("?") || urlString.hasSuffix("&") {
            urlString = String(urlString.dropLast())
        }

        return URL(string: urlString)
    }

    /// Generate description for AI system prompt
    func generatePromptDescription() -> String {
        var desc = "### \(id)\n"
        desc += "\(description)\n"
        desc += "App: \(appName)\n"

        if !parameters.isEmpty {
            desc += "Parameters:\n"
            for param in parameters {
                let required = param.isRequired ? "(required)" : "(optional)"
                desc += "- \(param.name) \(required): \(param.description)\n"
            }
        }

        return desc
    }
}

// MARK: - Port Category

enum PortCategory: String, Codable, CaseIterable, Sendable {
    case notes           // Obsidian, Bear, Apple Notes, Notion
    case tasks           // Things, Reminders, Todoist, OmniFocus
    case calendar        // Calendar, Fantastical
    case automation      // Shortcuts, Raycast
    case communication   // Mail, Messages
    case browser         // Safari, Chrome
    case media           // Music, Photos
    case developer       // Xcode, Terminal
    case finance         // Banking, crypto apps
    case health          // Health, fitness apps
    case custom          // User-defined

    var displayName: String {
        switch self {
        case .notes: return "Notes & Writing"
        case .tasks: return "Tasks & Reminders"
        case .calendar: return "Calendar & Events"
        case .automation: return "Automation"
        case .communication: return "Communication"
        case .browser: return "Browser"
        case .media: return "Media"
        case .developer: return "Developer Tools"
        case .finance: return "Finance"
        case .health: return "Health & Fitness"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .notes: return "doc.text"
        case .tasks: return "checklist"
        case .calendar: return "calendar"
        case .automation: return "gearshape.2"
        case .communication: return "message"
        case .browser: return "globe"
        case .media: return "play.circle"
        case .developer: return "hammer"
        case .finance: return "dollarsign.circle"
        case .health: return "heart"
        case .custom: return "puzzlepiece"
        }
    }
}

// MARK: - Port Invocation Type

enum PortInvocationType: String, Codable, Sendable {
    case urlScheme       // obsidian://new?name=X
    case xCallbackUrl    // app://x-callback-url/action?params
    case shortcut        // shortcuts://run-shortcut?name=X
    case universal       // Universal links (https://app.com/action)

    var displayName: String {
        switch self {
        case .urlScheme: return "URL Scheme"
        case .xCallbackUrl: return "x-callback-url"
        case .shortcut: return "Shortcut"
        case .universal: return "Universal Link"
        }
    }
}

// MARK: - Port Parameter

struct PortParameter: Codable, Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let description: String
    let type: PortParameterType
    let isRequired: Bool
    let defaultValue: String?
    let placeholder: String?

    init(
        name: String,
        description: String,
        type: PortParameterType = .string,
        isRequired: Bool = true,
        defaultValue: String? = nil,
        placeholder: String? = nil
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.placeholder = placeholder
    }
}

enum PortParameterType: String, Codable, Sendable {
    case string
    case text       // Multi-line text
    case url
    case date
    case boolean
    case number
    case choice     // Enum-like selection
}

// MARK: - User-Imported Shortcut

/// A Shortcut imported by the user (by name)
struct ImportedShortcut: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var description: String
    var inputDescription: String?  // What input the shortcut expects
    var isEnabled: Bool
    let importedAt: Date

    init(name: String, description: String = "", inputDescription: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.inputDescription = inputDescription
        self.isEnabled = true
        self.importedAt = Date()
    }

    /// Generate URL to run this shortcut
    func generateUrl(with input: String? = nil) -> URL? {
        var urlString = "shortcuts://run-shortcut?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"

        if let input = input, !input.isEmpty {
            urlString += "&input=text&text=\(input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input)"
        }

        return URL(string: urlString)
    }

    /// Convert to a PortRegistryEntry for unified handling
    func toPortEntry() -> PortRegistryEntry {
        PortRegistryEntry(
            id: "shortcut_\(id)",
            name: name,
            description: description.isEmpty ? "Run the '\(name)' shortcut" : description,
            appName: "Shortcuts",
            icon: "bolt.square",
            category: .automation,
            invocationType: .shortcut,
            isEnabled: isEnabled,
            isBuiltIn: false,
            parameters: inputDescription != nil ? [
                PortParameter(name: "input", description: inputDescription!, isRequired: false)
            ] : [],
            urlTemplate: "shortcuts://run-shortcut?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name){{input}}",
            appStoreUrl: nil,
            appScheme: "shortcuts"
        )
    }
}

// MARK: - Port Invocation Result

/// Result of invoking a port
enum PortInvocationResult: Sendable {
    case success(url: URL)
    case appNotInstalled(appStoreUrl: String?)
    case invalidParameters(missing: [String])
    case urlGenerationFailed
    case userCancelled
    case error(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - Port Invocation Request

/// A request to invoke a port (for approval flow)
struct PortInvocationRequest: Identifiable, Sendable {
    let id: UUID
    let port: PortRegistryEntry
    let parameters: [String: String]
    let requestedAt: Date

    init(port: PortRegistryEntry, parameters: [String: String]) {
        self.id = UUID()
        self.port = port
        self.parameters = parameters
        self.requestedAt = Date()
    }
}
