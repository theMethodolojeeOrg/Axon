//
//  MarkdownService.swift
//  Axon
//
//  Provides markdown rendering utilities and theming for the app
//

import SwiftUI
import MarkdownUI

// MARK: - Type Alias to Disambiguate from FirebaseAuth.Theme

/// Typealias to disambiguate MarkdownUI.Theme from FirebaseAuth.Theme
typealias MarkdownTheme = MarkdownUI.Theme

// MARK: - Axon Markdown Theme

extension MarkdownTheme {
    /// Custom Axon theme optimized for chat bubbles
    /// - Compact headings suitable for message context
    /// - Tighter spacing for conversational flow
    /// - Axon design system colors for dark mode
    static let axon: MarkdownTheme = .basic
        // Text styles - these are simpler for the compiler
        .text {
            ForegroundColor(AppColors.textPrimary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            ForegroundColor(AppColors.signalLichen)
            BackgroundColor(AppColors.substrateTertiary)
        }
        .link {
            ForegroundColor(AppColors.signalMercury)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        // Compact headings for chat bubbles
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.15))
                    ForegroundColor(AppColors.textPrimary)
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.1))
                    ForegroundColor(AppColors.textPrimary)
                }
                .markdownMargin(top: 6, bottom: 3)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.05))
                    ForegroundColor(AppColors.textPrimary)
                }
                .markdownMargin(top: 4, bottom: 2)
        }
        // Compact paragraph spacing
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: 6)
        }
        // Compact list items
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2)
        }
        // Styled code blocks (minimal here)
        //
        // Note: We now render fenced code blocks at the message layer (see
        // `AssistantMessageView`) so we can support:
        // - accurate language label
        // - perfect copy/download
        // - artifact expansion
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                    ForegroundColor(AppColors.signalLichen)
                }
                .padding(10)
                .background(AppColors.substrateTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .markdownMargin(top: 6, bottom: 6)
        }
        // Styled blockquotes
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    FontStyle(.italic)
                    ForegroundColor(AppColors.textSecondary)
                }
                .padding(.leading, 12)
                .overlay(
                    Rectangle()
                        .fill(AppColors.signalMercury.opacity(0.5))
                        .frame(width: 3),
                    alignment: .leading
                )
                .markdownMargin(top: 6, bottom: 6)
        }
}

// MARK: - Markdown Text View

/// A reusable view for rendering markdown content with the Axon theme
struct MarkdownTextView: View {
    let content: String
    
    init(_ content: String) {
        self.content = content
    }
    
    var body: some View {
        Markdown(content)
            .markdownTheme(MarkdownTheme.axon)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            MarkdownTextView("""
            # Heading 1
            ## Heading 2
            ### Heading 3
            
            This is a paragraph with **bold** and *italic* text.
            
            Here's some `inline code` in a sentence.
            
            ```swift
            let greeting = "Hello, World!"
            print(greeting)
            ```
            
            > A blockquote to showcase custom styling.
            
            - Bullet one
            - Bullet two
            - Bullet three
            """)
                .padding()
        }
        .padding(.vertical, 24)
    }
    .background(AppColors.substratePrimary)
}
