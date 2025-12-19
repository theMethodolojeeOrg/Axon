//
//  ChatMarkdownExporter.swift
//  Axon
//

import Foundation

struct ChatMarkdownExporter {
    func render(_ payload: ChatExportPayload) -> String {
        var out: [String] = []

        out.append("# \(escape(payload.conversation.title))")
        out.append("")

        out.append("- Conversation ID: `\(payload.conversation.id)`")
        out.append("- Project ID: `\(payload.conversation.projectId)`")
        if let userId = payload.conversation.userId {
            out.append("- User ID: `\(userId)`")
        }
        out.append("- Created: \(iso(payload.conversation.createdAt))")
        out.append("- Updated: \(iso(payload.conversation.updatedAt))")
        if let last = payload.conversation.lastMessageAt {
            out.append("- Last message: \(iso(last))")
        }
        out.append("- Exported: \(iso(payload.exportedAt))")

        if let overrides = payload.conversationOverrides {
            out.append("")
            out.append("## Conversation Overrides")
            if let provider = overrides.providerDisplayName {
                out.append("- Provider: \(escape(provider))")
            }
            if let model = overrides.modelDisplayName {
                out.append("- Model: \(escape(model))")
            }
            if let enabledTools = overrides.enabledToolIds {
                out.append("- Enabled tools: \(enabledTools.sorted().map { "`\($0)`" }.joined(separator: ", "))")
            }
        }

        out.append("")
        out.append("---")
        out.append("")

        for message in payload.messages {
            out.append("## \(message.role.rawValue.uppercased()) • \(iso(message.timestamp))")

            var meta: [String] = []
            if let provider = message.providerName { meta.append("Provider: \(escape(provider))") }
            if let model = message.modelName { meta.append("Model: \(escape(model))") }
            if let tokens = message.tokens { meta.append("Tokens: in \(tokens.input), out \(tokens.output), total \(tokens.total)") }
            if message.isEdited { meta.append("Edited") }

            if let hiddenReason = message.hiddenReason {
                meta.append("HiddenReason: \(escape(hiddenReason))")
            }

            if !meta.isEmpty {
                out.append("_\(meta.joined(separator: " • "))_")
                out.append("")
            }

            out.append(message.content.trimmingCharacters(in: .whitespacesAndNewlines))
            out.append("")

            // Attachment references (lightweight)
            if let attachments = message.attachments, !attachments.isEmpty {
                out.append("**Attachments**")
                for a in attachments {
                    let name = a.name ?? "(unnamed)"
                    let url = a.url ?? "(no url)"
                    out.append("- \(a.type.rawValue): \(escape(name)) — \(escape(url))")
                }
                out.append("")
            }

            // Tool calls (collapsed via HTML details)
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                out.append("<details>")
                out.append("<summary>Tool Calls (\(toolCalls.count))</summary>")
                out.append("")
                for call in toolCalls {
                    out.append("- **\(escape(call.name))** `\(call.id)`")
                    if let args = call.arguments {
                        out.append("  - args: \(escape(argsDescription(args)))")
                    }
                    if let result = call.result {
                        out.append("  - result: \(escape(result))")
                    }
                }
                out.append("")
                out.append("</details>")
                out.append("")
            }

            // Grounding sources
            if let sources = message.groundingSources, !sources.isEmpty {
                out.append("<details>")
                out.append("<summary>Grounding Sources (\(sources.count))</summary>")
                out.append("")
                for s in sources {
                    out.append("- [\(escape(s.title))](\(escape(s.url))) (`\(s.sourceType.rawValue)`)")
                }
                out.append("")
                out.append("</details>")
                out.append("")
            }

            // Reasoning (you asked to include it)
            if let reasoning = message.reasoning, !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append("<details>")
                out.append("<summary>Reasoning</summary>")
                out.append("")
                out.append("```text")
                out.append(reasoning)
                out.append("```")
                out.append("")
                out.append("</details>")
                out.append("")
            }

            out.append("---")
            out.append("")
        }

        return out.joined(separator: "\n")
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: "")
    }

    private func argsDescription(_ args: [String: AnyCodable]) -> String {
        // Keep it lightweight; JSON export has full structure.
        args.map { key, value in
            "\(key)=\(String(describing: value))"
        }.sorted().joined(separator: ", ")
    }
}
