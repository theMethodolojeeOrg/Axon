//
//  UseViewValidator.swift
//  Axon
//
//  Validates a USE view document against the bundled component catalog
//  before it is persisted. USEBridge renders unknown components as inline
//  error placeholders instead of throwing, so this is the only gate.
//
//  Documents come in two shapes:
//  - bare root spec: {"component": ...}
//  - wrapped: {"operations": [executor ops], "root": {spec}}
//

import Foundation
import USEAuthoringCore

@MainActor
enum UseViewValidator {

    struct ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        var isValid: Bool { errors.isEmpty }
    }

    /// Validate a USE view document (either shape).
    static func validate(_ document: [String: Any]) -> ValidationResult {
        var result = ValidationResult()

        let isWrapped = document["component"] == nil && document["swiftType"] == nil
            && (document["root"] != nil || document["operations"] != nil)

        if isWrapped {
            if let operations = document["operations"] {
                if let ops = operations as? [[String: Any]] {
                    validateOperations(ops, result: &result)
                } else {
                    result.errors.append("'operations' must be an array of operation objects like {\"op\": \"define\", ...}.")
                }
            }

            if let root = document["root"] as? [String: Any] {
                validateNode(root, path: "root", result: &result)
            } else {
                result.errors.append("Wrapped documents need a 'root' object: {\"operations\": [...], \"root\": {\"component\": ...}}.")
            }
        } else {
            validateNode(document, path: "root", result: &result)
        }

        return result
    }

    // MARK: - Node Validation

    private static func validateNode(
        _ node: [String: Any],
        path: String,
        lenientTemplate: Bool = false,
        result: inout ValidationResult
    ) {
        let typeValue = node["component"] ?? node["swiftType"]

        guard let type = typeValue as? String, !type.isEmpty else {
            result.errors.append("Node at \(path) is missing a 'component' string. Every node needs {\"component\": \"<type>\"}.")
            return
        }

        let key = type.lowercased()
        let catalog = UseComponentCatalogService.shared

        guard let schema = catalog.schema(for: key) else {
            result.errors.append("Unknown component '\(type)' at \(path). Call get_view_catalog for the list of valid components.")
            return
        }

        // Props
        if let rawProps = node["props"], !(rawProps is [String: Any]) {
            result.errors.append("'props' at \(path) must be an object.")
        }
        let props = node["props"] as? [String: Any] ?? [:]

        let knownPropNames = Set(schema.properties.map(\.name))
        for (propName, propValue) in props {
            // Action-valued props
            if actionProps.contains(propName) {
                validateAction(propValue, path: "\(path).props.\(propName)", result: &result)
                continue
            }
            // Spec-valued props
            if propName == "overlay" || propName == "mask" {
                validateSpecProp(propValue, name: propName, path: path, result: &result)
                continue
            }
            if propName == "toolbar" {
                validateToolbar(propValue, path: path, result: &result)
                continue
            }
            if propName == "sheet" {
                validateSheet(propValue, path: path, result: &result)
                continue
            }
            if propName == "alert" {
                validateAlert(propValue, path: path, result: &result)
                continue
            }
            // Unknown props are advisory only: USEBridge applies universal
            // modifier props (padding, blur, overlay, ...) to any component.
            if !knownPropNames.contains(propName) && !universalModifierProps.contains(propName) {
                if lenientTemplate, isTemplatePlaceholder(propValue) { continue }
                result.warnings.append("Prop '\(propName)' on '\(key)' at \(path) is not in the component's manifest; it may be ignored.")
            }
        }

        // Required props (advisory; skipped inside ForEach templates where
        // values are substituted per element)
        if !lenientTemplate {
            for prop in schema.properties where prop.required && props[prop.name] == nil {
                result.warnings.append("Component '\(key)' at \(path) is missing required prop '\(prop.name)'.")
            }
        }

        // ForEach: items + first-child template, validated leniently
        if key == "foreach" {
            validateForEach(node, props: props, path: path, result: &result)
            return
        }

        // Children
        if let rawChildren = node["children"] {
            guard let children = rawChildren as? [[String: Any]] else {
                result.errors.append("'children' at \(path) must be an array of node objects.")
                return
            }
            if !children.isEmpty && !schema.acceptsChildren {
                result.warnings.append("Component '\(key)' at \(path) does not accept children; they may be ignored.")
            }
            for (index, child) in children.enumerated() {
                validateNode(child, path: "\(path).children[\(index)]", lenientTemplate: lenientTemplate, result: &result)
            }
        }
    }

    // MARK: - ForEach

    private static func validateForEach(
        _ node: [String: Any],
        props: [String: Any],
        path: String,
        result: inout ValidationResult
    ) {
        // items: inline array or "$stateKey" reference
        if let items = props["items"] {
            let isArray = items is [Any]
            let isStateRef = (items as? String).map { $0.hasPrefix("$") && $0.count > 1 } ?? false
            if !isArray && !isStateRef {
                result.errors.append("ForEach at \(path) needs 'items' as an inline array or a '$stateKey' string.")
            }
        } else {
            result.errors.append("ForEach at \(path) is missing required prop 'items' (inline array or '$stateKey' string).")
        }

        guard let children = node["children"] as? [[String: Any]], let template = children.first else {
            result.errors.append("ForEach at \(path) needs a first child to use as the per-item template.")
            return
        }
        if children.count > 1 {
            result.warnings.append("ForEach at \(path) has \(children.count) children; only the first is used as the template.")
        }
        // Template is validated leniently: $item/$index placeholders are
        // substituted per element, so prop-level checks are advisory.
        validateNode(template, path: "\(path).children[0]", lenientTemplate: true, result: &result)
    }

    /// True for "$item", "$index", and "$item.<path>" template strings.
    private static func isTemplatePlaceholder(_ value: Any) -> Bool {
        guard let string = value as? String else { return false }
        return string == "$item" || string == "$index" || string.hasPrefix("$item.")
    }

    // MARK: - Complex Modifier Props

    private static func validateSpecProp(_ value: Any, name: String, path: String, result: inout ValidationResult) {
        guard let spec = value as? [String: Any] else {
            result.errors.append("'\(name)' at \(path) must be a child spec object like {\"component\": ...}.")
            return
        }
        validateNode(spec, path: "\(path).props.\(name)", result: &result)
    }

    private static func validateToolbar(_ value: Any, path: String, result: inout ValidationResult) {
        guard let items = value as? [[String: Any]] else {
            result.errors.append("'toolbar' at \(path) must be an array of child spec objects (each with an optional 'placement' prop).")
            return
        }
        for (index, item) in items.enumerated() {
            let itemPath = "\(path).props.toolbar[\(index)]"
            if let placement = (item["props"] as? [String: Any])?["placement"] as? String,
               !knownToolbarPlacements.contains(placement) {
                result.warnings.append("Toolbar placement '\(placement)' at \(itemPath) is not a known placement; it may fall back to automatic.")
            }
            validateNode(item, path: itemPath, result: &result)
        }
    }

    private static func validateSheet(_ value: Any, path: String, result: inout ValidationResult) {
        guard let sheet = value as? [String: Any] else {
            result.errors.append("'sheet' at \(path) must be an object: {\"isPresented\": \"<stateKey>\", \"content\": {<spec>}}.")
            return
        }
        if !(sheet["isPresented"] is String) || (sheet["isPresented"] as? String)?.isEmpty != false {
            result.errors.append("'sheet' at \(path) needs 'isPresented' as a non-empty state key string.")
        }
        if let content = sheet["content"] {
            validateSpecProp(content, name: "sheet.content", path: path, result: &result)
        } else {
            result.warnings.append("'sheet' at \(path) has no 'content' spec; the sheet will be empty.")
        }
    }

    private static func validateAlert(_ value: Any, path: String, result: inout ValidationResult) {
        guard let alert = value as? [String: Any] else {
            result.errors.append("'alert' at \(path) must be an object: {\"isPresented\": \"<stateKey>\", \"title\": ..., \"actions\": [...]}.")
            return
        }
        if !(alert["isPresented"] is String) || (alert["isPresented"] as? String)?.isEmpty != false {
            result.errors.append("'alert' at \(path) needs 'isPresented' as a non-empty state key string.")
        }
        if alert["title"] == nil {
            result.warnings.append("'alert' at \(path) has no 'title'.")
        }
        if let actions = alert["actions"] {
            guard let actionSpecs = actions as? [[String: Any]] else {
                result.errors.append("'alert.actions' at \(path) must be an array of child spec objects.")
                return
            }
            for (index, spec) in actionSpecs.enumerated() {
                validateNode(spec, path: "\(path).props.alert.actions[\(index)]", result: &result)
            }
        }
    }

    // MARK: - View Action Validation

    private static func validateAction(_ value: Any, path: String, result: inout ValidationResult) {
        guard let action = value as? [String: Any] else {
            result.errors.append("Action at \(path) must be an object like {\"type\": \"setState\", ...}.")
            return
        }

        guard let type = action["type"] as? String, !type.isEmpty else {
            result.errors.append("Action at \(path) is missing a 'type' string.")
            return
        }

        guard UseComponentCatalogService.supportedActionTypes.contains(type) else {
            let valid = UseComponentCatalogService.supportedActionTypes.sorted().joined(separator: ", ")
            result.errors.append("Unknown action type '\(type)' at \(path). Valid types: \(valid). (Executor ops like define/pipe/graph belong in the document's 'operations' array, not in actions.)")
            return
        }

        // Recurse into composite actions
        if type == "sequence" {
            if let nested = action["actions"] as? [Any] {
                for (index, nestedAction) in nested.enumerated() {
                    validateAction(nestedAction, path: "\(path).actions[\(index)]", result: &result)
                }
            } else {
                result.errors.append("'sequence' action at \(path) needs an 'actions' array.")
            }
        }

        if type == "conditional" || type == "if" {
            for branch in ["then", "else"] {
                if let nestedAction = action[branch] {
                    validateAction(nestedAction, path: "\(path).\(branch)", result: &result)
                }
            }
        }
    }

    // MARK: - Operations Validation

    /// Validate the document's top-level executor operations array.
    /// Hard-fails ops outside the safe allowlist, including ops nested in
    /// define bodies / if branches / forEach bodies.
    private static func validateOperations(_ operations: [[String: Any]], result: inout ValidationResult) {
        for (index, op) in operations.enumerated() {
            validateOperation(op, path: "operations[\(index)]", result: &result)
        }
    }

    private static func validateOperation(_ op: [String: Any], path: String, result: inout ValidationResult) {
        guard let name = op["op"] as? String, !name.isEmpty else {
            result.errors.append("Operation at \(path) is missing an 'op' string.")
            return
        }

        guard UseComponentCatalogService.safeOperationOps.contains(name) else {
            let valid = UseComponentCatalogService.safeOperationOps.sorted().joined(separator: ", ")
            result.errors.append("Operation '\(name)' at \(path) is not allowed in view documents. Allowed ops: \(valid).")
            return
        }

        // Shallow shape checks (advisory)
        switch name {
        case "define":
            if op["name"] == nil { result.warnings.append("'define' at \(path) has no 'name'.") }
            if op["body"] == nil { result.warnings.append("'define' at \(path) has no 'body'.") }
        case "call":
            if op["name"] == nil { result.warnings.append("'call' at \(path) has no 'name'.") }
        case "subscribe":
            if op["channel"] == nil { result.warnings.append("'subscribe' at \(path) has no 'channel'.") }
            if op["handler"] == nil { result.warnings.append("'subscribe' at \(path) has no 'handler'.") }
        case "pipe":
            if op["functions"] == nil { result.warnings.append("'pipe' at \(path) has no 'functions' array.") }
        case "graph":
            if op["nodes"] == nil { result.warnings.append("'graph' at \(path) has no 'nodes' array.") }
        default:
            break
        }

        // Recurse nested op arrays so blocked ops can't hide inside bodies:
        // define.body, if.then/else, forEach.do
        for nestedKey in ["body", "then", "else", "do"] {
            if let nestedOps = op[nestedKey] as? [[String: Any]] {
                for (index, nestedOp) in nestedOps.enumerated() {
                    validateOperation(nestedOp, path: "\(path).\(nestedKey)[\(index)]", result: &result)
                }
            }
        }
    }

    // MARK: - Modifier Prop Names

    /// Action-valued modifier props (validated as view actions).
    private static let actionProps: Set<String> = [
        "action", "onTap", "onAppear", "onDisappear"
    ]

    /// Known toolbar placement strings (advisory check only).
    private static let knownToolbarPlacements: Set<String> = [
        "automatic", "primaryAction", "confirmationAction", "cancellationAction",
        "destructiveAction", "principal", "navigation",
        "navigationBarLeading", "navigationBarTrailing", "bottomBar"
    ]

    /// Props USEBridge's modifier pipeline applies to any component,
    /// independent of the per-component manifest (see applyModifiers).
    private static let universalModifierProps: Set<String> = [
        // Layout & sizing
        "padding", "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight", "alignment",
        // Colors & visibility
        "background", "foregroundStyle", "color", "opacity", "hidden", "disabled",
        // Appearance
        "cornerRadius", "clipShape", "clipRadius", "borderColor", "borderWidth",
        "shadow", "shadowColor", "shadowRadius", "shadowX", "shadowY",
        // Transforms & effects
        "scaleEffect", "scaleAnchor", "rotation", "rotationAnchor", "offsetX", "offsetY", "blur",
        // Text styling
        "font", "fontWeight", "multilineTextAlignment", "lineLimit", "truncationMode",
        // Accessibility & navigation
        "accessibilityLabel", "navigationTitle", "searchable", "searchPrompt",
        // Complex (validated separately but never "unknown")
        "overlay", "overlayAlignment", "mask", "toolbar", "sheet", "alert",
        "onTap", "onAppear", "onDisappear",
        // State binding
        "stateKey"
    ]
}
