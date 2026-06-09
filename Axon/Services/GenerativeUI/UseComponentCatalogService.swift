//
//  UseComponentCatalogService.swift
//  Axon
//
//  Builds a compact, AI-consumable catalog of USE components and actions
//  from the manifests bundled in the USE-Package (USEManifests).
//

import Foundation
import USEAuthoringCore

@MainActor
final class UseComponentCatalogService {
    static let shared = UseComponentCatalogService()

    /// Actions implemented by USEBridge.executeAction. The bundled manifests
    /// may under-specify actions, so this list is authoritative for validation.
    static let supportedActionTypes: Set<String> = [
        "print", "log",
        "setState", "toggleState", "incrementState",
        "call", "emit",
        "sequence", "conditional", "if",
        "navigate", "sheet", "alert", "dismiss",
        "haptic", "openURL"
    ]

    /// Components whose manifests declare an action slot (`hasAction` is not
    /// surfaced by ComponentSchema, so these are listed explicitly).
    static let actionBearingComponents: Set<String> = [
        "button", "toggle", "menu", "navigationlink", "link"
    ]

    private var cachedCatalogJSON: String?

    private init() {}

    // MARK: - Loading

    /// Load the bundled manifests into ComponentCatalog once (bundle-static).
    private func ensureLoaded() {
        if ComponentCatalog.shared.components.isEmpty {
            ComponentCatalog.shared.load()
        }
    }

    /// Lowercased component keys valid in a USE spec's "component" field.
    var componentKeys: Set<String> {
        ensureLoaded()
        return Set(ComponentCatalog.shared.components.map(\.key))
    }

    /// Schema lookup for a component key (case-insensitive).
    func schema(for componentKey: String) -> ComponentSchema? {
        ensureLoaded()
        return ComponentCatalog.shared.component(named: componentKey)
    }

    // MARK: - Compact Catalog

    /// Compact JSON reference of all components/actions for the AI.
    /// Optionally filtered by a component-name substring.
    func compactCatalogJSON(filter: String? = nil) -> String {
        if filter == nil, let cached = cachedCatalogJSON {
            return cached
        }

        ensureLoaded()

        var components = ComponentCatalog.shared.components
        if let filter, !filter.isEmpty {
            let needle = filter.lowercased()
            components = components.filter { $0.key.contains(needle) }
        }

        let componentEntries: [[String: Any]] = components.map { schema in
            var entry: [String: Any] = ["type": schema.key]
            if schema.acceptsChildren { entry["children"] = true }
            if Self.actionBearingComponents.contains(schema.key) { entry["action"] = true }
            if let description = schema.description { entry["description"] = description }
            if !schema.properties.isEmpty {
                entry["props"] = schema.properties.map { prop -> [String: Any] in
                    var p: [String: Any] = ["name": prop.name, "type": prop.type]
                    if !prop.enumValues.isEmpty { p["values"] = prop.enumValues }
                    if prop.required { p["required"] = true }
                    return p
                }
            }
            return entry
        }

        let catalog: [String: Any] = [
            "specShape": [
                "component": "<type from components list>",
                "props": ["<prop name>": "<value>"],
                "children": ["<nested nodes, for container components>"]
            ],
            "components": componentEntries,
            "actions": Self.supportedActionTypes.sorted(),
            "actionShape": ["type": "<action type>", "key": "<state key for setState/toggleState/incrementState>", "value": "<for setState>"],
            "stateBindings": "Input components (textfield, toggle, slider, stepper, picker, datepicker) bind to shared view state via a 'stateKey' prop. Actions like setState/toggleState/incrementState mutate the same keys.",
            "universalModifierProps": [
                "padding", "frame", "background", "foregroundColor", "cornerRadius",
                "shadow", "opacity", "font", "fontWeight"
            ],
            "notes": "Set an 'action' prop on action-bearing components (button etc.) to an action object or a sequence. Use 'sequence' with an 'actions' array for multiple steps."
        ]

        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: catalog, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            json = string
        } else {
            json = "{}"
        }

        if filter == nil {
            cachedCatalogJSON = json
        }
        return json
    }
}
