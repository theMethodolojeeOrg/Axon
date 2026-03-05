//
//  ChatJSONExporter.swift
//  Axon
//

import Foundation

struct ChatJSONExporter {
    func encode(_ payload: ChatExportPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Keep dates readable; schema is explicit.
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }
}
