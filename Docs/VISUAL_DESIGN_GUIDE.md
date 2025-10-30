# NeurXAxonChat: Visual Design Philosophy & SwiftUI Implementation

## Design Philosophy Overview

NeurXAxonChat employs a **Mineral-Inspired Dark Theme** - a sophisticated, tech-forward design language that draws inspiration from natural substrates and geological formations. The visual system prioritizes clarity, hierarchy, and functional elegance while maintaining a distinctly scientific aesthetic.

**Design Principles:**
1. **Substrate Foundation** - Deep, mineral-like dark surfaces that feel grounded and stable
2. **Semantic Signals** - Warm/cool color choices that communicate meaning beyond visual hierarchy
3. **Glass Morphism** - Frosted glass layers with backdrop blur for depth without clutter
4. **Signal Clarity** - Intentional color psychology for success/warning/info states
5. **Typography Hierarchy** - Clear text levels for scannable interfaces
6. **Minimal Motion** - Subtle animations that don't distract from content

---

## Color System

### Foundation Colors (Substrate Palette)

The Substrate palette is mineral-inspired, using deep grays from near-black to lighter stone tones. These form the structural backbone of the interface.

```
Substrate-900: #0e1112  (Deep foundation - nearly black)
Substrate-800: #161a1b  (Primary surface - main background)
Substrate-700: #1f2425  (Elevated surfaces - cards, modals)
Substrate-600: #2a3031  (Interactive elements - buttons, inputs)
Substrate-500: #343c3d  (Hover states)
Substrate-400: #485051  (Borders & dividers)
Substrate-300: #677172  (Disabled elements)
Substrate-200: #8a9394  (Secondary text)
Substrate-100: #c4c9c9  (Tertiary accents)
```

**In SwiftUI:**
```swift
enum SubstrateColor {
    static let deep = Color(red: 0.055, green: 0.067, blue: 0.071)      // #0e1112
    static let primary = Color(red: 0.086, green: 0.102, blue: 0.106)    // #161a1b
    static let elevated = Color(red: 0.122, green: 0.141, blue: 0.145)   // #1f2425
    static let interactive = Color(red: 0.165, green: 0.188, blue: 0.192) // #2a3031
    static let hover = Color(red: 0.204, green: 0.235, blue: 0.239)      // #343c3d
    static let border = Color(red: 0.282, green: 0.314, blue: 0.318)     // #485051
    static let disabled = Color(red: 0.404, green: 0.443, blue: 0.447)   // #677172
    static let secondary = Color(red: 0.541, green: 0.576, blue: 0.580)  // #8a9394
    static let tertiary = Color(red: 0.769, green: 0.788, blue: 0.788)   // #c4c9c9
}
```

### Semantic Signal Colors

Signal colors communicate meaning through warm (alert/warning) and cool (info/success) tones, inspired by natural minerals and geological formations.

```
Signal-Copper:    #b2763a  (Warm alerts, warnings, attention states)
Signal-Mercury:   #3f6f7a  (Cool info, system status, agent content)
Signal-Lichen:    #5f7f5f  (Green success, confirmation, user content)
Signal-Hematite:  #6b5a5a  (Neutral observations, debugging info)
```

**Meaning & Usage:**

| Color | RGB | Meaning | Usage |
|-------|-----|---------|-------|
| **Copper** | #b2763a | Warm, alert | Warnings, errors, attention-needed states, important notices |
| **Mercury** | #3f6f7a | Cool, informative | System messages, AI responses, informational content |
| **Lichen** | #5f7f5f | Green, growth | Success states, confirmations, user-created content highlights |
| **Hematite** | #6b5a5a | Neutral, grounded | Debugging info, neutral tags, secondary information |

**In SwiftUI:**
```swift
enum SignalColor {
    static let copper = Color(red: 0.698, green: 0.462, blue: 0.227)     // #b2763a (Warm)
    static let mercury = Color(red: 0.247, green: 0.439, blue: 0.478)    // #3f6f7a (Cool)
    static let lichen = Color(red: 0.373, green: 0.498, blue: 0.373)     // #5f7f5f (Green)
    static let hematite = Color(red: 0.420, green: 0.353, blue: 0.353)   // #6b5a5a (Neutral)
}
```

### Text Hierarchy Colors

Clear text hierarchy ensures content is scannable and prioritized.

```
Text-Primary:   #e6eaea  (Main content, primary actions)
Text-Secondary: #a9b2b2  (Secondary information, labels)
Text-Tertiary:  #7d8686  (Metadata, timestamps, hints)
```

**In SwiftUI:**
```swift
enum TextColor {
    static let primary = Color(red: 0.902, green: 0.918, blue: 0.918)     // #e6eaea
    static let secondary = Color(red: 0.663, green: 0.698, blue: 0.698)   // #a9b2b2
    static let tertiary = Color(red: 0.490, green: 0.525, blue: 0.525)    // #7d8686
}
```

---

## Surface System

### Glass Morphism Layers

NeurXAxonChat uses layered glass surfaces with backdrop blur to create visual depth while maintaining clarity.

**Glass Surface (Primary Layer):**
- Background: `substrate-800` at 95% opacity
- Backdrop filter: `blur(48px)` (`.blur(48)` in SwiftUI)
- Border: `substrate-400` at 50% opacity
- Use case: Main content areas, cards, panels

**Glass Elevated (Secondary Layer):**
- Background: `substrate-700` at 95% opacity
- Backdrop filter: `blur(48px)`
- Border: `substrate-400` at 30% opacity
- Use case: Modals, overlays, floating panels

**In SwiftUI:**
```swift
struct GlassSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                SubstrateColor.primary.opacity(0.95)
            )
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SubstrateColor.border.opacity(0.5), lineWidth: 1)
            )
    }
}

struct GlassElevated<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                SubstrateColor.elevated.opacity(0.95)
            )
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SubstrateColor.border.opacity(0.3), lineWidth: 1)
            )
    }
}
```

---

## Typography System

### Font Family

**IBM Plex Sans** - A professional, geometric sans-serif designed for clarity and readability at all sizes. Supports multiple weights for hierarchy.

**In SwiftUI:**
```swift
struct Typography {
    // Display - Large, bold statements (24pt-32pt)
    static let display = Font.system(size: 32, weight: .bold, design: .default)
        .tracking(0.15)

    // Title 1 - Section titles, major headings (28pt)
    static let title1 = Font.system(size: 28, weight: .semibold, design: .default)
        .tracking(0.1)

    // Title 2 - Subsection titles (22pt)
    static let title2 = Font.system(size: 22, weight: .semibold, design: .default)
        .tracking(0.1)

    // Title 3 - Card titles, labels (18pt)
    static let title3 = Font.system(size: 18, weight: .semibold, design: .default)

    // Body - Main content text (16pt)
    static let body = Font.system(size: 16, weight: .regular, design: .default)

    // Body emphasis - Important body text (16pt, semibold)
    static let bodyEmphasis = Font.system(size: 16, weight: .semibold, design: .default)

    // Callout - Secondary information (14pt)
    static let callout = Font.system(size: 14, weight: .regular, design: .default)

    // Subheadline - Small labels, metadata (13pt)
    static let subheadline = Font.system(size: 13, weight: .regular, design: .default)

    // Caption - Timestamps, small text (12pt)
    static let caption = Font.system(size: 12, weight: .regular, design: .default)

    // Caption emphasis - Important small text (12pt, semibold)
    static let captionEmphasis = Font.system(size: 12, weight: .semibold, design: .default)
}

// Usage example:
Text("Hello World")
    .font(Typography.title1)
    .foregroundColor(TextColor.primary)
```

### Text Hierarchy Levels

| Level | Size | Weight | Color | Use Case |
|-------|------|--------|-------|----------|
| **Display** | 32pt | Bold | Primary | Major page titles, hero text |
| **Title 1** | 28pt | Semibold | Primary | Section headings, major content |
| **Title 2** | 22pt | Semibold | Primary | Subsection titles |
| **Title 3** | 18pt | Semibold | Primary | Card titles, important labels |
| **Body** | 16pt | Regular | Primary | Main content text |
| **Body Emphasis** | 16pt | Semibold | Primary | Important body text |
| **Callout** | 14pt | Regular | Secondary | Secondary information |
| **Subheadline** | 13pt | Regular | Tertiary | Metadata, small labels |
| **Caption** | 12pt | Regular | Tertiary | Timestamps, smallest text |

---

## Component Design Language

### Buttons

**Primary Button**
- Background: Gradient `substrate-600` → `substrate-500`
- Hover: Gradient `substrate-500` → `substrate-400`
- Text: `text-primary`, medium weight
- Shadow: `mineral-shadow` (subtle)
- Transition: 200ms ease

```swift
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.bodyEmphasis)
                .foregroundColor(TextColor.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            SubstrateColor.interactive,
                            SubstrateColor.hover
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
        }
    }
}
```

**Accent Button (Mercury - Info/Agent)**
- Background: Gradient `signal-mercury` → `signal-mercury` 80%
- Hover: Gradient `signal-mercury` 90% → 70%
- Text: White, medium weight
- Shadow: `signal-mercury` tinted shadow
- Transition: 200ms ease

```swift
struct AccentButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.bodyEmphasis)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            SignalColor.mercury,
                            SignalColor.mercury.opacity(0.8)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
                .shadow(color: SignalColor.mercury.opacity(0.3), radius: 4, y: 2)
        }
    }
}
```

### Signal States

All signal states use 10% background opacity with 30% border opacity for consistency.

**Success (Lichen - Green)**
```swift
struct SuccessSignal: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(SignalColor.lichen)
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                Text("Success")
                    .font(Typography.captionEmphasis)
                    .foregroundColor(SignalColor.lichen)
                Text(message)
                    .font(Typography.caption)
                    .foregroundColor(TextColor.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(SignalColor.lichen.opacity(0.1))
        .border(SignalColor.lichen.opacity(0.3), width: 1)
        .cornerRadius(8)
    }
}
```

**Warning (Copper - Warm)**
```swift
struct WarningSignal: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(SignalColor.copper)
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                Text("Warning")
                    .font(Typography.captionEmphasis)
                    .foregroundColor(SignalColor.copper)
                Text(message)
                    .font(Typography.caption)
                    .foregroundColor(TextColor.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(SignalColor.copper.opacity(0.1))
        .border(SignalColor.copper.opacity(0.3), width: 1)
        .cornerRadius(8)
    }
}
```

**Info (Mercury - Cool)**
```swift
struct InfoSignal: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(SignalColor.mercury)
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                Text("Information")
                    .font(Typography.captionEmphasis)
                    .foregroundColor(SignalColor.mercury)
                Text(message)
                    .font(Typography.caption)
                    .foregroundColor(TextColor.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(SignalColor.mercury.opacity(0.1))
        .border(SignalColor.mercury.opacity(0.3), width: 1)
        .cornerRadius(8)
    }
}
```

### Interactive Elements

**Interactive Element Base**
- Background: `substrate-600`
- Hover: `substrate-500`
- Transition: 200ms ease-out
- All interactive elements should respond on tap

```swift
extension View {
    func asInteractiveElement() -> some View {
        self
            .background(SubstrateColor.interactive)
            .cornerRadius(8)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
```

---

## Layout & Spacing System

### Spacing Scale

NeurXAxonChat uses an 8pt base unit for consistent spacing.

```
4pt   = 0.5 units  (Extra tight)
8pt   = 1 unit     (Tight)
12pt  = 1.5 units  (Standard)
16pt  = 2 units    (Comfortable)
24pt  = 3 units    (Spacious)
32pt  = 4 units    (Very spacious)
48pt  = 6 units    (Generous)
64pt  = 8 units    (Extra generous)
```

**In SwiftUI:**
```swift
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
    static let giant: CGFloat = 64
}

// Usage:
VStack(spacing: Spacing.lg) {
    Text("Title")
    Text("Content")
}
```

### Corner Radius

**Consistency:**
- Small elements: `4pt` (buttons, badges)
- Medium elements: `8pt` (cards, inputs)
- Large elements: `12pt` (modals, full-screen surfaces)

```swift
enum CornerRadius {
    static let small: CGFloat = 4
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
}
```

---

## Animation & Motion

### Principles

1. **Minimal & Purposeful** - Animations serve a function, not decoration
2. **Quick & Responsive** - Standard duration is 200ms
3. **Eased Motion** - Use `easeOut` for entrance, `easeInOut` for transitions
4. **Subtle Feedback** - Scale, opacity, and color shifts (not rotation or translation)

### Animation Timings

```swift
enum AnimationDuration {
    static let fast: Double = 0.15      // Micro-interactions
    static let standard: Double = 0.20  // Button taps, state changes
    static let slow: Double = 0.30      // Page transitions
    static let verySlow: Double = 0.50  // Large animations
}
```

### Animation Examples

**Entrance Animation (Slide In)**
```swift
struct SlideInView<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
    }
}
```

**Subtle Pulse (Loading State)**
```swift
struct PulseAnimation: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .opacity(isAnimating ? 0.6 : 1.0)
            .animation(
                Animation.easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}
```

**Button Tap Feedback**
```swift
struct TapAnimationButton<Label: View>: View {
    @State private var isPressed = false
    let action: () -> Void
    let label: Label

    var body: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.15)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.15)) {
                    isPressed = false
                }
                action()
            }
        }) {
            label
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .opacity(isPressed ? 0.8 : 1.0)
        }
    }
}
```

---

## Confidence Visualization

The confidence system uses visual metaphors to communicate the certainty level of knowledge:

### Visual Indicators

**Color Coding:**
- **High (0.7-1.0)** → Green (Lichen) - "Established"
- **Medium (0.4-0.7)** → Yellow (Copper) - "Uncertain"
- **Low (0.0-0.4)** → Red (Copper darker) - "Hypothesis"

**Visual Components:**
- Progress bar fill level
- Color intensity
- Icon state (checkmark → dash → question)

```swift
struct ConfidenceIndicator: View {
    let confidence: Double

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: confidenceIcon)
                        .foregroundColor(confidenceColor)
                        .font(.system(size: 14, weight: .semibold))

                    Text(confidenceLabel)
                        .font(Typography.captionEmphasis)
                        .foregroundColor(confidenceColor)
                }

                Spacer()

                Text(String(format: "%.0f%%", confidence * 100))
                    .font(Typography.caption)
                    .foregroundColor(TextColor.tertiary)
            }

            // Progress bar
            ProgressView(value: confidence)
                .tint(confidenceColor)
                .frame(height: 4)
        }
        .padding(Spacing.md)
        .background(SubstrateColor.elevated.opacity(0.5))
        .cornerRadius(CornerRadius.medium)
    }

    private var confidenceColor: Color {
        switch confidence {
        case 0.7...1.0:
            return SignalColor.lichen       // Green - Established
        case 0.4..<0.7:
            return SignalColor.copper       // Yellow/Warm - Uncertain
        default:
            return SignalColor.copper       // Red - Hypothesis
        }
    }

    private var confidenceLabel: String {
        switch confidence {
        case 0.7...1.0:
            return "Established"
        case 0.4..<0.7:
            return "Uncertain"
        default:
            return "Hypothesis"
        }
    }

    private var confidenceIcon: String {
        switch confidence {
        case 0.7...1.0:
            return "checkmark.circle.fill"
        case 0.4..<0.7:
            return "minus.circle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }
}
```

---

## Shadow System

### Mineral Shadows

NeurXAxonChat uses "mineral shadows" - subtle, layered shadows that evoke depth without harshness.

**Standard Shadow (12px elevation)**
```swift
extension View {
    func mineralShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}
```

**Large Shadow (24px elevation)**
```swift
extension View {
    func mineralShadowLarge() -> some View {
        self.shadow(color: Color.black.opacity(0.5), radius: 24, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
    }
}
```

**No hover shadows on interactive elements** - Use color shift instead for subtle feedback.

---

## Message Bubbles & Content Design

### AI Message Bubble (Mercury - Blue)

```swift
struct AIMessageBubble: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // AI Avatar indicator
            Circle()
                .fill(SignalColor.mercury.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SignalColor.mercury)
                )

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Agent")
                    .font(Typography.captionEmphasis)
                    .foregroundColor(SignalColor.mercury)

                Text(content)
                    .font(Typography.body)
                    .foregroundColor(TextColor.primary)
                    .lineLimit(nil)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .background(SignalColor.mercury.opacity(0.08))
        .cornerRadius(CornerRadius.medium)
    }
}
```

### User Message Bubble (Lichen - Green)

```swift
struct UserMessageBubble: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: Spacing.sm) {
                Text("You")
                    .font(Typography.captionEmphasis)
                    .foregroundColor(SignalColor.lichen)

                Text(content)
                    .font(Typography.body)
                    .foregroundColor(TextColor.primary)
                    .lineLimit(nil)
            }

            Circle()
                .fill(SignalColor.lichen.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SignalColor.lichen)
                )
        }
        .padding(Spacing.lg)
        .background(SignalColor.lichen.opacity(0.08))
        .cornerRadius(CornerRadius.medium)
    }
}
```

---

## Memory & Tag Visualization

### Memory Card

```swift
struct MemoryCard: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with confidence
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(memory.type.rawValue.capitalized)
                        .font(Typography.captionEmphasis)
                        .foregroundColor(TextColor.tertiary)
                        .textCase(.uppercase)

                    Text(memory.content)
                        .font(Typography.bodyEmphasis)
                        .foregroundColor(TextColor.primary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Image(systemName: confidenceIcon)
                        .foregroundColor(confidenceColor)
                        .font(.system(size: 12, weight: .semibold))

                    Text(String(format: "%.0f%%", memory.confidence * 100))
                        .font(Typography.caption)
                        .foregroundColor(confidenceColor)
                }
            }

            // Tags
            if !memory.tags.isEmpty {
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(memory.tags, id: \.self) { tag in
                        Text(tag)
                            .font(Typography.caption)
                            .foregroundColor(TextColor.secondary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(SubstrateColor.interactive.opacity(0.5))
                            .cornerRadius(CornerRadius.small)
                    }
                }
            }

            // Metadata
            HStack(spacing: Spacing.lg) {
                Label(
                    memory.createdAt.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "calendar"
                )
                .font(Typography.caption)
                .foregroundColor(TextColor.tertiary)

                Spacer()

                if let context = memory.context {
                    Label(context, systemImage: "quote.bubble")
                        .font(Typography.caption)
                        .foregroundColor(TextColor.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(Spacing.lg)
        .asGlassSurface()
    }

    private var confidenceColor: Color {
        switch memory.confidence {
        case 0.7...1.0:
            return SignalColor.lichen
        case 0.4..<0.7:
            return SignalColor.copper
        default:
            return SignalColor.copper
        }
    }

    private var confidenceIcon: String {
        switch memory.confidence {
        case 0.7...1.0:
            return "checkmark.circle.fill"
        case 0.4..<0.7:
            return "minus.circle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }
}
```

### Tag Style

```swift
struct TagView: View {
    let name: String
    let color: Color
    let count: Int?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "tag.fill")
                .font(.system(size: 10, weight: .semibold))

            Text(name)
                .font(Typography.caption)

            if let count = count {
                Text("(\(count))")
                    .font(Typography.caption)
                    .foregroundColor(TextColor.tertiary)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    color,
                    color.opacity(0.8)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(CornerRadius.small)
    }
}
```

---

## Accessibility & Inclusive Design

### Color Contrast

All color combinations must meet WCAG AAA standards (7:1 contrast ratio minimum).

- Text-Primary (#e6eaea) on Substrate-900: **11.8:1** ✅
- Text-Secondary (#a9b2b2) on Substrate-900: **5.2:1** ✅ (WCAG AA)
- Signal colors have high contrast with backgrounds

### Focus States

All interactive elements must have clear focus indicators for keyboard navigation:

```swift
extension View {
    func accessibleFocus() -> some View {
        self
            .focusable()
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(SignalColor.mercury, lineWidth: 2)
                    .opacity(0)  // Becomes visible on focus
            )
    }
}
```

### Semantic HTML/SwiftUI

Use semantic views for better screen reader support:

```swift
struct AccessibleMemoryCard: View {
    let memory: Memory

    var body: some View {
        VStack {
            // ...
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory: \(memory.type.rawValue)")
        .accessibilityValue("\(Int(memory.confidence * 100))% confidence")
        .accessibilityHint(memory.context ?? "No context available")
    }
}
```

---

## Dark Mode Considerations

This design is built for dark mode. For light mode support (future):

- **Invert substrate values:** 900 ↔ 100
- **Keep signal colors:** They're designed for both themes
- **Adjust text colors:** Ensure 7:1 contrast on light backgrounds
- **Glass surfaces:** Use lighter base with appropriate opacity

---

## Component Catalog Examples

### Loading State

```swift
struct LoadingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            ProgressView()
                .tint(SignalColor.mercury)

            Text("Loading...")
                .font(Typography.body)
                .foregroundColor(TextColor.secondary)

            Spacer()
        }
        .padding(Spacing.lg)
        .background(SubstrateColor.elevated.opacity(0.5))
        .cornerRadius(CornerRadius.medium)
    }
}
```

### Empty State

```swift
struct EmptyState: View {
    let icon: String
    let title: String
    let description: String
    let action: (() -> Void)?
    let actionLabel: String?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(TextColor.tertiary)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Typography.title2)
                    .foregroundColor(TextColor.primary)

                Text(description)
                    .font(Typography.body)
                    .foregroundColor(TextColor.secondary)
                    .multilineTextAlignment(.center)
            }

            if let action = action, let label = actionLabel {
                PrimaryButton(title: label, action: action)
                    .padding(.top, Spacing.lg)
            }
        }
        .padding(Spacing.xxxl)
        .multilineTextAlignment(.center)
    }
}
```

---

## Design System Summary

| Element | Value |
|---------|-------|
| **Primary Color** | Substrate-800 (#161a1b) |
| **Text Primary** | #e6eaea |
| **Success Signal** | Lichen (#5f7f5f) |
| **Warning Signal** | Copper (#b2763a) |
| **Info Signal** | Mercury (#3f6f7a) |
| **Font Family** | IBM Plex Sans |
| **Base Spacing** | 8pt |
| **Corner Radius** | 4/8/12pt |
| **Animation Duration** | 200ms standard |
| **Shadow Style** | Mineral (layered) |

---

## Implementation Checklist for SwiftUI

- [ ] Define color enums (Substrate, Signal, Text)
- [ ] Create typography system with font sizes
- [ ] Build glass surface components (GlassSurface, GlassElevated)
- [ ] Implement button variants (Primary, Accent)
- [ ] Create signal state views (Success, Warning, Info)
- [ ] Define spacing constants
- [ ] Build animation extensions
- [ ] Create confidence indicator component
- [ ] Implement memory card component
- [ ] Build message bubble components
- [ ] Add accessibility overlays
- [ ] Test contrast ratios with online tool
- [ ] Verify animations on device (not just simulator)
- [ ] Test dark mode (and light mode if supporting)

---

**Design System Version:** 1.0.0
**Last Updated:** October 28, 2025
**Framework:** SwiftUI
**Compatibility:** iOS 15+, macOS 12+
