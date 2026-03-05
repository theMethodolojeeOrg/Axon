# Settings View Modularization Plan

This document describes the process for transforming monolithic settings views into modular, maintainable components that leverage shared components from `SettingsComponents.swift`.

---

## Goals

1. **Consistency**: All settings screens use the same visual components and patterns
2. **Maintainability**: Each section lives in its own file, making changes isolated
3. **Reusability**: Common patterns are extracted into shared components
4. **Simplicity**: Main view files become thin orchestrators (~30-50 lines)

---

## Reference Implementation: MemorySettingsView

The `MemorySettingsView/` directory demonstrates the complete transformation:

```
MemorySettingsView/
├── MemorySettingsView.swift          # ~46 lines - thin orchestrator
└── Components/
    ├── AnalyticsSection.swift
    ├── DebuggingSection.swift
    ├── EpistemicEngineSection.swift
    ├── HeartbeatSection.swift
    ├── HeuristicsSection.swift
    ├── InternalThreadSection.swift
    ├── MemoryRetrievalSection.swift
    ├── MemorySystemSection.swift
    ├── MemoryTypesSection.swift
    ├── MemoryTypeInfo.swift          # Sub-component used by MemoryTypesSection
    ├── NotificationsSection.swift
    └── SmallModelOptimizationSection.swift
```

### Key Pattern: The Thin Orchestrator

The main view file is just a VStack composing section components:

```swift
struct MemorySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MemorySystemSection(viewModel: viewModel)
            if viewModel.settings.memoryEnabled {
                MemoryRetrievalSection(viewModel: viewModel)
            }
            MemoryTypesSection(viewModel: viewModel)
            // ... more sections
        }
    }
}
```

---

## Shared Components Available (SettingsComponents.swift)

Before creating new components, check if these existing shared components fit your needs:

### Layout Components

| Component | Purpose | Example Usage |
|-----------|---------|---------------|
| `SettingsSection` | Section wrapper with title and GlassCard | Wraps each logical section |
| `UnifiedSettingsSection` | Section with title only (no card) | Alternative section style |
| `SettingsCard` | Rounded card with border | Container for grouped content |
| `SettingsSubviewContainer` | ScrollView wrapper for pushed views | Navigation destinations |

### Interactive Components

| Component | Purpose | Example Usage |
|-----------|---------|---------------|
| `SettingsToggleRow` | Toggle with title + description | Enable/disable features |
| `SettingsToggleRowSimple` | Toggle with title only | Secondary toggles |
| `SettingsSliderRow` | Slider with title, value, labels | Thresholds, intervals |
| `SettingsOptionCard` | Radio-button style selection | Exclusive choices |
| `ExpandableSettingsSection` | Collapsible section with header | Tool categories |

### Display Components

| Component | Purpose | Example Usage |
|-----------|---------|---------------|
| `SettingsFeatureRow` | Icon + text row | Feature lists, info items |
| `SettingsCategoryRow` | Navigation row with icon | Category navigation |
| `SettingsStatusCard` | Status with icon + action | Connection status |
| `SettingsInfoBanner` | Informational banner | Tips, warnings |
| `ConfigurationStatusBadge` | Configured/not configured badge | API key status |
| `SecureInputField` | Password field with show/hide | API keys, secrets |

---

## Modularization Process

### Phase 1: Analysis

1. **Read the source file** completely
2. **Identify logical sections** - each `SettingsSection(title:)` call is typically one section
3. **Map to shared components** - identify which `SettingsComponents.swift` items apply
4. **Identify custom components** - patterns used only in this view that need extraction
5. **Note alert/sheet dependencies** - modals that need to move with their triggers

### Phase 2: Directory Setup

Create the component directory structure:

```
{SettingsViewName}/
├── {SettingsViewName}.swift
└── Components/
    └── (empty initially)
```

### Phase 3: Extract Sections (Bottom-Up)

Extract in order of dependency (helpers first):

1. **Extract helper views first** (e.g., `MemoryTypeInfo`)
2. **Extract self-contained sections** (no dependencies on sibling sections)
3. **Extract sections with shared state** (pass viewModel)
4. **Move alerts/sheets with their trigger sections**

### Phase 4: Refactor to Shared Components

Replace inline patterns with shared components:

```swift
// BEFORE: Inline toggle
HStack {
    Image(systemName: "gear")
    VStack(alignment: .leading) {
        Text("Setting Name")
        Text("Description")
    }
    Spacer()
    Toggle("", isOn: $binding)
}

// AFTER: Shared component
SettingsToggleRow(
    title: "Setting Name",
    description: "Description",
    isOn: $binding
)
```

### Phase 5: Simplify Main View

The main view should become a simple orchestrator:

```swift
struct {SettingsViewName}: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Section1(viewModel: viewModel)
            Section2(viewModel: viewModel)
            // Conditional sections
            if viewModel.settings.someFlag {
                Section3(viewModel: viewModel)
            }
        }
    }
}
```

---

## Example: DeveloperSettingsView Transformation

### Current State (920 lines)

```
DeveloperSettingsViews/
├── DeveloperSettingsView.swift    # 920 lines - monolithic
├── DeveloperConsoleView.swift     # Separate subview
├── LogSettingsSection.swift       # Already extracted!
└── Components/                    # Empty
```

### Identified Sections

| Section | Lines | Shared Components Applicable |
|---------|-------|------------------------------|
| Developer Tools Header | 42-66 | `SettingsFeatureRow` |
| Screenshot/Demo Mode | 69-191 | `SettingsToggleRow`, custom buttons |
| Chat Debug | 194-247 | `SettingsToggleRow`, `SettingsFeatureRow` |
| Console Logging | 250-260 | Already extracted to `LogSettingsSection` |
| Generative UI | 263-309 | `SettingsFeatureRow`, NavigationLink |
| What Happens | 312-328 | `SettingsFeatureRow` |
| AIP Identity | 331-393 | `SettingsStatusCard`, custom button |
| Complete Reset | 396-486 | `SettingsFeatureRow`, custom button |
| Alerts | 516-555 | Move with trigger sections |
| Private Methods | 558-905 | Stay in main file or move to ViewModel |

### Proposed Structure After Transformation

```
DeveloperSettingsViews/
├── DeveloperSettingsView.swift        # ~60 lines - orchestrator
├── DeveloperConsoleView.swift         # Keep as-is
├── LogSettingsSection.swift           # Already extracted
└── Components/
    ├── DeveloperHeaderSection.swift   # ~30 lines
    ├── DemoModeSection.swift          # ~150 lines (includes alerts)
    ├── ChatDebugSection.swift         # ~60 lines
    ├── GenerativeUISection.swift      # ~50 lines
    ├── WhatHappensSection.swift       # ~25 lines
    ├── AIPIdentitySection.swift       # ~80 lines (includes alert)
    └── CompleteResetSection.swift     # ~120 lines (includes alert)
```

### Components to Add to SettingsComponents.swift

After modularization, consider promoting reusable patterns:

1. **`SettingsActionButton`** - Destructive action button pattern (used in Demo Mode, AIP Reset, Complete Reset)
2. **`SettingsInfoCard`** - Icon + title + description card (used in Developer Header)

---

## Checklist for Each Section Extraction

- [ ] Create new file in `Components/` directory
- [ ] Move struct definition
- [ ] Add required imports (`SwiftUI`, domain types)
- [ ] Add `@ObservedObject var viewModel: SettingsViewModel` if needed
- [ ] Move associated `@State` variables
- [ ] Move associated alerts/sheets (keep with trigger)
- [ ] Move private helper methods used only by this section
- [ ] Update main view to use the new component
- [ ] Verify build succeeds
- [ ] Test functionality unchanged

---

## Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Section files | `{FeatureName}Section.swift` | `DemoModeSection.swift` |
| Helper components | `{Purpose}Info.swift` or `{Purpose}Row.swift` | `MemoryTypeInfo.swift` |
| Main view | `{Category}SettingsView.swift` | `DeveloperSettingsView.swift` |
| Directory | `{Category}SettingsViews/` | `DeveloperSettingsViews/` |

---

## Migration Priority

Suggested order based on complexity and ROI:

1. **DeveloperSettingsView** (920 lines) - Highest impact
2. **PrivacySettingsViews** - If similarly monolithic
3. **AutomationSettingsViews** - Check for monolithic files
4. **ProvidersSettingsViews** - Check for monolithic files
5. **ModelSettingsViews** - Check for monolithic files

---

## Quality Checks

After modularization:

1. **Main view < 60 lines** - Should be pure composition
2. **Each section < 150 lines** - If larger, consider sub-components
3. **No duplicate patterns** - Use shared components
4. **Consistent styling** - Same spacing, colors, typography
5. **Preview works** - Add `#Preview` to each component file

---

## Appendix: SettingsSection vs UnifiedSettingsSection

Two section wrapper styles exist:

**`SettingsSection`** (from SettingsView.swift):
- Uppercase title with tertiary color
- Wrapped in `GlassCard`
- Used by most settings screens

**`UnifiedSettingsSection`** (from SettingsComponents.swift):
- Headline-style title
- No card wrapper
- Used by GeneralSettingsView style

Choose based on the parent screen's existing style for consistency.
