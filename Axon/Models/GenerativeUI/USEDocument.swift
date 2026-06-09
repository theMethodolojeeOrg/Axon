//
//  USEDocument.swift
//  Axon
//
//  Codable wrapper around an open-form USE spec dictionary
//  (the {"component": ..., "props": ..., "children": ...} tree
//  rendered by USEBridge from the USE-Package).
//

import Foundation

/// A USE view document: the root spec node stored as type-erased JSON.
struct USEDocument: Codable, Equatable, Sendable {
    var spec: [String: AnyCodable]

    init(spec: [String: AnyCodable]) {
        self.spec = spec
    }

    /// Wrap a raw JSON dictionary (e.g. parsed tool input) into a document.
    static func from(_ dict: [String: Any]) -> USEDocument {
        USEDocument(spec: dict.mapValues(wrap))
    }

    /// Unwrap to the raw dictionary form consumed by USEBridge.render(_:).
    func asDictionary() -> [String: Any] {
        spec.mapValues(Self.unwrap)
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
