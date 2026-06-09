//
//  UseComponentCatalogService.swift
//  Axon
//
//  Builds a compact, AI-consumable catalog of USE components, modifiers,
//  view actions, and executor operations from the manifests bundled in
//  the USE-Package (USEManifests).
//

import Foundation
import USEAuthoringCore
import USECore

/// Security policy applied to executors that run AI-authored view documents.
enum USEViewPolicy {
    /// Strict policy further restricted to hermetic operations: no file
    /// loads, no policy mutation, no shared-registry injection.
    static let aiDocument = SecurityPolicy.strict
        .restrictingOperations(to: UseComponentCatalogService.safeOperationOps)
}

@MainActor
final class UseComponentCatalogService {
    static let shared = UseComponentCatalogService()

    /// Action types implemented by USEBridge.executeAction — valid in
    /// `action` / `onTap` / `onAppear` / `onDisappear` props. These are
    /// VIEW actions, distinct from executor operations below.
    static let supportedActionTypes: Set<String> = [
        "print", "log",
        "setState", "toggleState", "incrementState",
        "call", "emit",
        "sequence", "conditional", "if",
        "navigate", "sheet", "alert", "dismiss",
        "haptic", "openURL"
    ]

    /// Executor operations allowed in a document's top-level "operations"
    /// array. Single source of truth shared by UseViewValidator and the
    /// runtime policy (USEViewPolicy.aiDocument). Deliberately excludes
    /// loadManifest/loadOperational/policy/register/forEachChild so AI
    /// documents stay hermetic.
    static let safeOperationOps: Set<String> = [
        "set", "get", "if", "forEach",
        "define", "call", "subscribe", "emit",
        "connect", "pipe", "graph",
        "log", "validate"
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

    /// Compact JSON reference of the full authoring surface for the AI.
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
            if !schema.platforms.isEmpty { entry["platforms"] = schema.platforms }
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
            "documentShape": [
                "simple": "A bare root spec: {\"component\": \"vstack\", \"props\": {...}, \"children\": [...]}",
                "withLogic": "{\"operations\": [<executor ops, run ONCE at view setup>], \"root\": {<spec>}} — define functions and seed state in operations, then trigger them from buttons with a {\"type\": \"call\", \"name\": ...} action."
            ],
            "specShape": [
                "component": "<type from components list>",
                "props": ["<prop name>": "<value>"],
                "children": ["<nested nodes, for container components>"]
            ],
            "components": componentEntries,
            "viewActions": [
                "types": Self.supportedActionTypes.sorted(),
                "shape": ["type": "<action type>", "key": "<state key for setState/toggleState/incrementState>", "value": "<for setState>"],
                "usedIn": "the 'action' prop on action-bearing components, and the onTap/onAppear/onDisappear modifier props",
                "note": "Prefer the sheet/alert MODIFIERS (toggle a state key) over the sheet/alert/navigate ACTIONS — presentation actions emit to a channel with no host handler in this app."
            ],
            "operations": [
                "ops": Self.safeOperationOps.sorted(),
                "shapes": [
                    "set": "{op, key, value}",
                    "define": "{op, name, body: [<ops>]}",
                    "call": "{op, name, args?, into?}",
                    "subscribe": "{op, channel, handler}",
                    "emit": "{op, channel, payload?, mode?: sync|async}",
                    "pipe": "{op, functions: [<names>], args?, into?} — chains left-to-right",
                    "connect": "{op, from, to, toInput, fromOutput?, args?, toArgs?, into?}",
                    "graph": "{op, nodes: [{id, function, args}], edges: [{from, to, fromOutput?, toInput}], into?} — topological execution, cycles error"
                ],
                "note": "Operations go in the document's top-level 'operations' array, NOT in action props. They run once when the view loads; buttons invoke defined functions with the 'call' VIEW action."
            ],
            "modifierProps": [
                "simple": [
                    "padding", "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
                    "alignment", "background", "foregroundStyle", "color", "opacity", "hidden", "disabled",
                    "cornerRadius", "clipShape", "clipRadius", "borderColor", "borderWidth",
                    "shadow", "shadowColor", "shadowRadius", "shadowX", "shadowY",
                    "scaleEffect", "scaleAnchor", "rotation", "rotationAnchor", "offsetX", "offsetY", "blur",
                    "font", "fontWeight", "multilineTextAlignment", "lineLimit", "truncationMode",
                    "accessibilityLabel", "navigationTitle"
                ],
                "complex": [
                    "overlay": "<child spec> (+ overlayAlignment: <alignment string>)",
                    "mask": "<child spec>",
                    "toolbar": "[<child specs, each with optional placement prop>]",
                    "sheet": "{isPresented: <stateKey>, content: <child spec>}",
                    "alert": "{isPresented: <stateKey>, title, message?, actions: [<child specs>]}",
                    "searchable": "<stateKey string> (+ searchPrompt: <string>)",
                    "onTap": "<view action dict>",
                    "onAppear": "<view action dict>",
                    "onDisappear": "<view action dict>"
                ],
                "note": "Modifier props apply to any component, set directly in its props object."
            ],
            "foreach": "ForEach repeats its FIRST child as a template. props.items is an inline array or a '$stateKey' string. Inside the template use '$item', '$index', or '$item.<path>' — substituted per element.",
            "stateBindings": "Input components (textfield, toggle, slider, stepper, picker, datepicker) bind to shared view state via a 'stateKey' prop. View actions setState/toggleState/incrementState mutate the same keys; '$key' text content reads them."
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
