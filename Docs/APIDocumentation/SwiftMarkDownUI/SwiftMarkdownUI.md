Below is a self-contained Markdown documentation file you can drop into a `README.md` or dedicated docs page for `swift-markdown-ui` / `MarkdownUI`. It focuses on installation, core APIs, theming, and practical usage, based on the official package materials and docs while avoiding verbatim duplication.[1][2][3]

## Overview

MarkdownUI is a Swift package that renders GitHub‑flavored Markdown natively in SwiftUI, supporting headings, lists (including task lists), blockquotes, images, code blocks, tables, thematic breaks, links, and styled inline text.[1][2][4]
It targets Apple platforms (macOS, iOS, tvOS, watchOS) and integrates as a normal SwiftUI view, so Markdown content participates in layout, theming, accessibility, and state like any other view.[1][3]

Key points:

- Renders GitHub‑flavored Markdown with a native SwiftUI view called `Markdown`.[1][4]
- Provides a `MarkdownContent` type to pre-parse Markdown in your model layer for performance and reuse.[2][4]
- Exposes a powerful theming system (`Theme`, `markdownTheme`, `markdownTextStyle`, `markdownBlockStyle`) to customize text and block appearance.[1][3]

### Platform and feature support

Minimum OS versions for the package:[1][2]

- macOS 12+, iOS 15+, tvOS 15+, watchOS 8+ for core rendering.[1][2]
- Some advanced layout features (like tables or complex multi-image paragraphs) require macOS 13+/iOS 16+/tvOS 16+/watchOS 9+.[1][2]

## Installation

MarkdownUI is distributed as a Swift Package and uses the standard SPM workflow.[1][2]

### Swift Package Manager (SPM)

Add the package to your `Package.swift` (example for a library target):[2]

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/gonzalezreal/swift-markdown-ui",
        .upToNextMajor(from: "2.0.2")
    )
]

targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "MarkdownUI", package: "swift-markdown-ui")
        ]
    )
]
```

Then import it where you use it:[2]

```swift
import MarkdownUI
```

### Xcode project integration

To use MarkdownUI directly in an Xcode app project, add it as a package dependency from the IDE:[1][2]

1. In Xcode, open **File → Add Packages…**.[1][2]
2. Paste `https://github.com/gonzalezreal/swift-markdown-ui` into the search field, choose a version rule (for example “Up to Next Major”), and add the package.[1][2]
3. Link the **MarkdownUI** product to your application target under the **Frameworks, Libraries, and Embedded Content** section.[1][2]

## Core usage

The main entry point is the `Markdown` view, which you can initialize from a raw Markdown string, from a `MarkdownContent` value, or by using a builder-style DSL.[1][4][3]

### From a Markdown string

For simple cases, pass a Markdown string directly to `Markdown`:[2][4]

```swift
import SwiftUI
import MarkdownUI

struct ContentView: View {
    private let text = """
    ## Hello Markdown
    This is **Markdown** rendered with `MarkdownUI`.
    """

    var body: some View {
        Markdown(text)
    }
}
```

You can optionally configure a `baseURL` for resolving relative links and an `imageBaseURL` for resolving image references, which is helpful when content comes from external sources.[4][3]

### Using `MarkdownContent` (pre-parsed)

`MarkdownContent` lets you parse Markdown once (e.g., in your model layer) and reuse the parsed representation in views, reducing work during view updates.[1][2][4]  

```swift
// Model or data layer
let cachedMarkdown = MarkdownContent("""
You can parse **once** and reuse this content across views.
""")

// View layer
struct ContentView: View {
    var body: some View {
        Markdown(cachedMarkdown)
    }
}
```

`MarkdownContent` is value-typed, so it fits cleanly into Swift data models and can be passed around or cached as needed.[1][2]  

### Builder-style DSL

For more composable UIs, you can build Markdown content with a Swift DSL that mixes raw Markdown strings with structured elements like headings, paragraphs, and inline components.[1][2][4]

```swift
struct ContentView: View {
    var body: some View {
        Markdown {
            """
            ## Builder-based content
            You can mix raw Markdown with structured nodes.
            """

            Heading(.level2) {
                "Structured section"
            }

            Paragraph {
                "Combine "
                Strong("inline styles")
                " and "
                InlineLink(
                    "documentation",
                    destination: URL(string: "https://swiftpackageindex.com/gonzalezreal/swift-markdown-ui")!
                )
                "."
            }
        }
    }
}
```

The builder supports nodes such as `Heading`, `Paragraph`, `Strong`, `Emphasis`, `InlineCode`, `InlineLink`, images, lists, and more, mapping closely to GitHub‑flavored Markdown constructs.[1][4][3]

## Styling and theming

MarkdownUI ships with a basic default theme and a theming system that lets you either pick a prebuilt look (such as a GitHub-like style) or define and apply your own theme.[1][3]

### Using built-in themes

Apply a predefined theme to a single `Markdown` view or an enclosing view hierarchy using the `markdownTheme(_:)` modifier:[1][3]

```swift
Markdown("""
> A quote rendered with a GitHub-like theme.
""")
.markdownTheme(.gitHub)
```

Because `markdownTheme` is a view modifier, you can put it high in your view tree to style multiple `Markdown` views consistently.[1][3]

### Overriding text styles

You can override specific text styles (for example code, links, or emphasis) from the current theme using `markdownTextStyle(_:textStyle:)`.[1][3]

```swift
Markdown("Inline `code` can be styled.")
    .markdownTextStyle(\.code) {
        FontFamilyVariant(.monospaced)
        FontSize(.em(0.85))
        ForegroundColor(.purple)
        BackgroundColor(Color.purple.opacity(0.25))
    }
```

This mechanism allows fine-grained control of typography while preserving the rest of the theme’s behavior.[1][3]

### Overriding block styles

Block-level elements (like blockquotes, lists, paragraphs, or tables) can be customized using `markdownBlockStyle(_:body:)`.[1][3]

```swift
Markdown("""
> A stylized quote block.
""")
.markdownBlockStyle(\.blockquote) { configuration in
    configuration.label
        .padding()
        .markdownTextStyle {
            FontWeight(.semibold)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.teal)
                .frame(width: 4)
        }
        .background(Color.teal.opacity(0.15))
}
```

The `configuration.label` inside the block-style closure is the default-styled content, which you can further decorate with any SwiftUI modifiers.[1][3]

### Defining a custom theme

To get full control, you can construct your own `Theme` by chaining text and block style definitions.[1][3]

```swift
extension Theme {
    static let appTheme = Theme()
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
        }
        .link {
            ForegroundColor(.purple)
        }
        .paragraph { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.25))
                .markdownMargin(top: 0, bottom: 16)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.25))
        }
}
```

You apply a custom theme the same way as built-in ones: `.markdownTheme(.appTheme)`, which makes it easy to share typography and layout across your app.[1][3]

## Advanced notes and references

Certain Markdown features (like tables, some image layouts, and potentially more complex blocks) require newer OS versions due to underlying SwiftUI capabilities, so testing on your minimum supported platform is recommended.[1][2]
The official API reference and DocC documentation for MarkdownUI are hosted on the Swift Package Index, which is the authoritative source for symbol-level details, overloads, and additional examples.[1][5][3]

For deeper dives on design choices and rendering behavior, the author has published articles explaining how MarkdownUI improves Markdown rendering in SwiftUI while staying compatible with GitHub‑flavored Markdown.[6][3]
This document respects the project’s MIT-licensed code and original documentation by summarizing concepts in new words; for exact legal terms or the latest updates, always refer to the upstream repository and `LICENSE`/README files.[1][2]

Sources
[1] gonzalezreal/swift-markdown-ui: Display and customize ... - GitHub https://github.com/gonzalezreal/swift-markdown-ui
[2] swift-markdown-ui - Swift Package Registry https://swiftpackageregistry.com/gonzalezreal/swift-markdown-ui
[3] MarkdownUI | Documentation - Swift Package Index https://swiftpackageindex.com/gonzalezreal/swift-markdown-ui/2.4.1/documentation/markdownui
[4] Markdown | Documentation - Swift Package Index https://swiftpackageindex.com/gonzalezreal/swift-markdown-ui/2.4.1/documentation/markdownui/markdown
[5] swift-markdown-ui https://swiftpackageindex.com/gonzalezreal/swift-markdown-ui
[6] Better Markdown Rendering in SwiftUI - Guille Gonzalez https://gonzalezreal.github.io/2023/02/18/better-markdown-rendering-in-swiftui.html
[7] markiv/MarkdownUI: Render Markdown text in SwiftUI https://github.com/markiv/MarkdownUI
[8] Guille Gonzalez's Post https://www.linkedin.com/posts/guillermogonzalezreal_github-gonzalezrealswift-markdown-ui-activity-7053605264779788288-u7p5
[9] Creating Instructions with Markdown Syntax https://docs.skillable.com/docs/creating-instructions-with-markdown-syntax
[10] GitHub Trends Weekly : gonzalezreal/swift-markdown-ui - X https://x.com/CocoaDevBlogs/status/1889134273438847098
[11] Basic Syntax https://www.markdownguide.org/basic-syntax/
[12] wilmaplus/MarkdownUI: Render Flexible Markdown text in ... https://github.com/wilmaplus/MarkdownUI
[13] Markdown style guide | styleguide - Google https://google.github.io/styleguide/docguide/style.html
[14] SwiftUI Markdown rendering is too slow https://www.reddit.com/r/iOSProgramming/comments/1okapua/swiftui_markdown_rendering_is_too_slow_switched/
[15] Swift Package Index: Auto-generating, Auto-hosting, and Auto ... https://forums.swift.org/t/swift-package-index-auto-generating-auto-hosting-and-auto-updating-docc-documentation/57806
[16] Extended Syntax https://www.markdownguide.org/extended-syntax/
[17] GitHub Trends for today https://sparrowcode.io/en/frameworks/github-trending/repositories/today
[18] Markdown | Documentation - GitHub Pages https://swiftlang.github.io/swift-markdown/documentation/markdown/
[19] Github Markdown - rendering code blocks with XML & HTML https://stackoverflow.com/questions/34638927/github-markdown-rendering-code-blocks-with-xml-html-kramdown-vs-redcarpet
[20] Swift Package Manager SPM Tutorial 2025 – Add, Create & Remove ... https://www.youtube.com/watch?v=2Q-iM1MXIbs
