//
//  ToolRequestEnvelope.swift
//  Axon
//
//  Normalizes the many envelope shapes AIs produce in ```tool_request```
//  blocks into the canonical raw-input string the tool routers consume.
//
//  Canonical shape: {"tool": "<id>", "query": "<JSON-encoded string>"}
//  Also accepted (previously silently dropped, yielding misleading
//  "Missing required parameter" errors):
//    {"tool": ..., "query": {<object>}}
//    {"tool": ..., "input": {<object>}} / "parameters": {<object>}
//    {"tool": ..., <params as top-level fields>}
//

import Foundation

enum ToolRequestEnvelope {

    /// Extract the raw input string from a parsed tool-request JSON envelope.
    ///
    /// Precedence (string forms first to preserve existing behavior exactly;
    /// object forms and the top-level fallback only apply where the old
    /// parsers returned "" or failed to decode):
    /// 1. "parameters" object — string query/path/input inside it, else an
    ///    object under those keys, else the parameters object itself
    /// 2. flat string under query/memory/path/input/data
    /// 3. flat OBJECT under query/input/data — serialized to a JSON string
    /// 4. any other top-level fields besides tool — collected + serialized
    /// 5. flat "content" string (content-as-query)
    /// 6. "" (tools with no required parameters)
    static func extractQuery(from json: [String: Any], toolId: String) -> String {
        // 1. Nested parameters object
        if let params = json["parameters"] as? [String: Any] {
            if let q = params["query"] as? String { return q }
            if let q = params["path"] as? String { return q }
            if let q = params["input"] as? String { return q }
            for key in ["query", "input"] {
                if let object = params[key] as? [String: Any], let s = serialize(object) {
                    return s
                }
            }
            // The parameters object IS the input. "content" stays out so
            // write-style tools keep receiving it via extractContent.
            var payload = params
            payload.removeValue(forKey: "content")
            if !payload.isEmpty, let s = serialize(payload) { return s }
        }

        // 2. Flat string aliases
        if let q = json["query"] as? String { return q }
        if let q = json["memory"] as? String { return q }
        if let q = json["path"] as? String { return q }
        if let q = json["input"] as? String { return q }
        if let q = json["data"] as? String { return q }

        // 3. Flat object payloads under query-ish keys
        for key in ["query", "input", "data"] {
            if let object = json[key] as? [String: Any], let s = serialize(object) {
                return s
            }
        }

        // 4. Generalized top-level fallback: the model sent the parameters
        //    as sibling fields of "tool" (e.g. {"tool": "create_view",
        //    "name": ..., "document": {...}}). Reconstruct them as the input.
        //    A lone "content" key is NOT consumed here so content-as-query
        //    behavior below stays intact.
        var topLevel = json
        topLevel.removeValue(forKey: "tool")
        let nonContentKeys = topLevel.keys.filter { $0 != "content" }
        if !nonContentKeys.isEmpty, let s = serialize(topLevel) {
            return s
        }

        // 5. Content-only request: content is the query
        if let c = json["content"] as? String { return c }

        // 6. No parameters
        return ""
    }

    /// Extract a separate content field (write-style tools sending path
    /// in query and file content separately).
    static func extractContent(from json: [String: Any]) -> String? {
        if let params = json["parameters"] as? [String: Any],
           let content = params["content"] as? String {
            return content
        }

        // Flat format: only treat content as separate when a query-ish key
        // also exists (otherwise content IS the query)
        if json["query"] != nil || json["path"] != nil || json["input"] != nil {
            return json["content"] as? String
        }

        return nil
    }

    private static func serialize(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}
