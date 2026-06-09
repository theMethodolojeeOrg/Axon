//
//  UseViewPatchApplier.swift
//  Axon
//
//  Applies targeted patch operations to a USE spec document.
//  Node paths are arrays of child indices from the root:
//  [] = root, [0] = first child, [0,2] = third child of first child
//  (same convention as the legacy generative UI canvas).
//

import Foundation

enum UseViewPatchError: LocalizedError {
    case invalidOp(String)
    case invalidPath([Int], reason: String)
    case missingField(op: String, field: String)

    var errorDescription: String? {
        switch self {
        case .invalidOp(let op):
            return "Unknown patch op '\(op)'. Valid ops: setProp, removeProp, setComponent, insertChild, removeChild, replaceChild, replaceNode."
        case .invalidPath(let path, let reason):
            return "Invalid path \(path): \(reason)"
        case .missingField(let op, let field):
            return "Patch op '\(op)' is missing required field '\(field)'."
        }
    }
}

enum UseViewPatchApplier {

    /// Apply patch operations in order to a USE spec document.
    /// Throws on the first failing patch; the caller re-validates the
    /// result and persists only if valid (atomic update).
    static func apply(_ patches: [[String: Any]], to document: [String: Any]) throws -> [String: Any] {
        var result = document
        for patch in patches {
            result = try apply(patch, to: result)
        }
        return result
    }

    private static func apply(_ patch: [String: Any], to document: [String: Any]) throws -> [String: Any] {
        guard let op = patch["op"] as? String else {
            throw UseViewPatchError.missingField(op: "?", field: "op")
        }

        let path = (patch["path"] as? [Int])
            ?? (patch["path"] as? [Any])?.compactMap { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue }
            ?? []

        switch op {
        case "setProp":
            guard let key = patch["key"] as? String else {
                throw UseViewPatchError.missingField(op: op, field: "key")
            }
            guard let value = patch["value"] else {
                throw UseViewPatchError.missingField(op: op, field: "value")
            }
            return try mutateNode(in: document, at: path) { node in
                var props = node["props"] as? [String: Any] ?? [:]
                props[key] = value
                node["props"] = props
            }

        case "removeProp":
            guard let key = patch["key"] as? String else {
                throw UseViewPatchError.missingField(op: op, field: "key")
            }
            return try mutateNode(in: document, at: path) { node in
                var props = node["props"] as? [String: Any] ?? [:]
                props.removeValue(forKey: key)
                node["props"] = props
            }

        case "setComponent":
            guard let value = patch["value"] as? String else {
                throw UseViewPatchError.missingField(op: op, field: "value")
            }
            return try mutateNode(in: document, at: path) { node in
                node["component"] = value
            }

        case "insertChild":
            guard let newNode = patch["node"] as? [String: Any] else {
                throw UseViewPatchError.missingField(op: op, field: "node")
            }
            let index = (patch["index"] as? Int) ?? Int.max
            return try mutateNode(in: document, at: path) { node in
                var children = node["children"] as? [[String: Any]] ?? []
                children.insert(newNode, at: min(max(index, 0), children.count))
                node["children"] = children
            }

        case "removeChild":
            guard let index = patch["index"] as? Int else {
                throw UseViewPatchError.missingField(op: op, field: "index")
            }
            return try mutateNode(in: document, at: path) { node in
                var children = node["children"] as? [[String: Any]] ?? []
                guard index >= 0 && index < children.count else {
                    throw UseViewPatchError.invalidPath(path + [index], reason: "child index \(index) out of range (0..<\(children.count))")
                }
                children.remove(at: index)
                node["children"] = children
            }

        case "replaceChild":
            guard let index = patch["index"] as? Int else {
                throw UseViewPatchError.missingField(op: op, field: "index")
            }
            guard let newNode = patch["node"] as? [String: Any] else {
                throw UseViewPatchError.missingField(op: op, field: "node")
            }
            return try mutateNode(in: document, at: path) { node in
                var children = node["children"] as? [[String: Any]] ?? []
                guard index >= 0 && index < children.count else {
                    throw UseViewPatchError.invalidPath(path + [index], reason: "child index \(index) out of range (0..<\(children.count))")
                }
                children[index] = newNode
                node["children"] = children
            }

        case "replaceNode":
            guard let newNode = patch["node"] as? [String: Any] else {
                throw UseViewPatchError.missingField(op: op, field: "node")
            }
            if path.isEmpty {
                return newNode
            }
            let parentPath = Array(path.dropLast())
            let index = path.last!
            return try mutateNode(in: document, at: parentPath) { node in
                var children = node["children"] as? [[String: Any]] ?? []
                guard index >= 0 && index < children.count else {
                    throw UseViewPatchError.invalidPath(path, reason: "child index \(index) out of range (0..<\(children.count))")
                }
                children[index] = newNode
                node["children"] = children
            }

        default:
            throw UseViewPatchError.invalidOp(op)
        }
    }

    // MARK: - Tree Navigation

    /// Apply a mutation to the node at `path`, rebuilding the tree on the way up.
    private static func mutateNode(
        in document: [String: Any],
        at path: [Int],
        _ mutation: (inout [String: Any]) throws -> Void
    ) throws -> [String: Any] {
        var node = document

        if path.isEmpty {
            try mutation(&node)
            return node
        }

        let index = path[0]
        guard var children = node["children"] as? [[String: Any]] else {
            throw UseViewPatchError.invalidPath(path, reason: "node has no children array")
        }
        guard index >= 0 && index < children.count else {
            throw UseViewPatchError.invalidPath(path, reason: "child index \(index) out of range (0..<\(children.count))")
        }

        children[index] = try mutateNode(in: children[index], at: Array(path.dropFirst()), mutation)
        node["children"] = children
        return node
    }
}
