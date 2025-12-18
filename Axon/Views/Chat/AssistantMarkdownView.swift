//
//  AssistantMarkdownView.swift
//  Axon
//
//  Renders assistant markdown while replacing fenced code blocks with
//  custom ChatGPT/Claude-like code boxes.
//

import SwiftUI
import MarkdownUI

struct AssistantMarkdownView: View {
    let content: String

    private var segments: [MarkdownSegment] {
        FencedCodeParser.split(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                switch segment {
                case .markdown(let markdown):
                    Markdown(markdown)
                        .markdownTheme(MarkdownTheme.axon)
                        .textSelection(.enabled)
                        // Prevent parent ScrollView/LazyVStack measurement oddities
                        // (helps avoid clipping/truncation of long assistant messages).
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                case .code(let language, let code):
                    // Special handling for tool_request blocks - show actionable UI
                    if language?.lowercased() == "tool_request" {
                        ToolRequestCodeBlockView(code: code)
                    } else {
                        CodeBlockView(language: language, code: code) {
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(AppColors.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        AssistantMarkdownView(content: """
        Here is some text.

        ```swift
        struct Foo {
            let bar: String
        }
        ```

        More text.
        """)
        .padding()
        .background(AppColors.substratePrimary)
    }
}
