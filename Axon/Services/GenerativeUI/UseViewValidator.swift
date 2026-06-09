//
//  UseViewValidator.swift
//  Axon
//
//  Validates a USE spec document against the bundled component catalog
//  before it is persisted. USEBridge renders unknown components as inline
//  error placeholders instead of throwing, so this is the only gate.
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

    /// Validate a USE spec document (the raw {"component": ...} tree).
    /// Errors block saving; warnings are advisory (returned to the model
    /// alongside success).
    static func validate(_ document: [String: Any]) -> ValidationResult {
        var result = ValidationResult()
        validateNode(document, path: "root", result: &result)
        return result
    }

    // MARK: - Node Validation

    private static func validateNode(_ node: [String: Any], path: String, result: inout ValidationResult) {
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
            if propName == "action" {
                validateAction(propValue, path: "\(path).props.action", result: &result)
                continue
            }
            // Unknown props are advisory only: USEBridge applies universal
            // modifier props (padding, frame, background, ...) to any component.
            if !knownPropNames.contains(propName) && !universalModifierProps.contains(propName) {
                result.warnings.append("Prop '\(propName)' on '\(key)' at \(path) is not in the component's manifest; it may be ignored.")
            }
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
                validateNode(child, path: "\(path).children[\(index)]", result: &result)
            }
        }
    }

    // MARK: - Action Validation

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
            result.errors.append("Unknown action type '\(type)' at \(path). Valid types: \(valid).")
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

    // MARK: - Universal Modifier Props

    /// Props USEBridge's modifier pipeline applies to any component,
    /// independent of the per-component manifest (see applyModifiers).
    private static let universalModifierProps: Set<String> = [
        "padding", "width", "height", "maxWidth", "maxHeight",
        "minWidth", "minHeight", "background", "foregroundStyle",
        "cornerRadius", "clipShape", "opacity", "hidden", "disabled",
        "shadow", "shadowColor", "shadowRadius", "shadowX", "shadowY",
        "borderColor", "borderWidth", "stateKey", "font", "fontWeight"
    ]
}
