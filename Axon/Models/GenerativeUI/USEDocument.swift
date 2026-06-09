//
//  USEDocument.swift
//  Axon
//
//  Codable wrapper around an open-form USE spec dictionary
//  (the {"component": ..., "props": ..., "children": ...} tree
//  rendered by USEBridge from the USE-Package).
//

import Foundation

/// A USE view document. Two stored shapes are supported:
/// - bare root spec: {"component": ..., "props": ..., "children": ...}
/// - wrapped: {"operations": [executor ops], "root": {spec}} — operations
///   run once per view instance against a persistent USEExecutor before
///   the root renders (Phase 7 function abstraction).
struct USEDocument: Codable, Equatable, Sendable {
    var spec: [String: AnyCodable]

    init(spec: [String: AnyCodable]) {
        self.spec = spec
    }

    /// Wrap a raw JSON dictionary (e.g. parsed tool input) into a document.
    static func from(_ dict: [String: Any]) -> USEDocument {
        USEDocument(spec: dict.mapValues(wrap))
    }

    /// Unwrap to the full stored dictionary (wrapper included, if any).
    func asDictionary() -> [String: Any] {
        spec.mapValues(Self.unwrap)
    }

    // MARK: - Shape Accessors

    /// The renderable root spec. A document is "wrapped" only when it has a
    /// top-level "root" object and no top-level component identity of its own.
    var rootSpec: [String: Any] {
        let full = asDictionary()
        if let root = full["root"] as? [String: Any],
           full["component"] == nil, full["swiftType"] == nil {
            return root
        }
        return full
    }

    /// Executor operations to run once at view setup (wrapped shape only).
    var operations: [[String: Any]] {
        let full = asDictionary()
        guard full["component"] == nil, full["swiftType"] == nil else { return [] }
        return full["operations"] as? [[String: Any]] ?? []
    }

    var hasOperations: Bool {
        !operations.isEmpty
    }

    // MARK: - Any <-> AnyCodable Bridging

    private static func wrap(_ value: Any) -> AnyCodable {
        switch value {
        case is NSNull:
            return .null
        case let number as NSNumber:
            // NSNumber bridges Bool/Int/Double indistinguishably via `as?`;
            // inspect the underlying CF type to keep 1 != true and 2 != 2.0
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if CFNumberIsFloatType(number) {
                return .double(number.doubleValue)
            }
            return .int(number.intValue)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map(wrap))
        case let dict as [String: Any]:
            return .object(dict.mapValues(wrap))
        default:
            return .string(String(describing: value))
        }
    }

    private static func unwrap(_ value: AnyCodable) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .array(let array):
            return array.map(unwrap)
        case .object(let object):
            return object.mapValues(unwrap)
        }
    }
}
