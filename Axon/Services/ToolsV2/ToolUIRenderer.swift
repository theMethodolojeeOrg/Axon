//
//  ToolUIRenderer.swift
//  Axon
//
//  Created for ToolsV2 plugin system.
//
//  Generates SwiftUI views from JSON UI configuration in tool manifests.
//

import SwiftUI

// MARK: - Tool UI Renderer

/// Renders SwiftUI views from tool manifest UI configuration
@MainActor
struct ToolUIRenderer {

    // MARK: - Input Form Rendering

    /// Render an input form from tool UI config
    /// - Parameters:
    ///   - config: The input form configuration
    ///   - parameters: Tool parameter definitions for validation
    ///   - values: Binding to form values
    ///   - onSubmit: Called when form is submitted
    @ViewBuilder
    static func renderInputForm(
        config: ToolInputFormConfig,
        parameters: [String: ToolParameterV2]?,
        values: Binding<[String: Any]>,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let fields = config.fields {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    renderFormField(
                        field: field,
                        parameter: parameters?[field.param],
                        value: bindingForField(field.param, in: values)
                    )
                }
            }

            Button(action: onSubmit) {
                Text(config.submitLabel ?? "Submit")
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.signalMercury)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }

    /// Render a single form field
    @ViewBuilder
    static func renderFormField(
        field: ToolFormField,
        parameter: ToolParameterV2?,
        value: Binding<Any?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label
            if let label = field.label {
                HStack(spacing: 4) {
                    Text(label)
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textPrimary)

                    if parameter?.isRequired == true {
                        Text("*")
                            .foregroundColor(AppColors.accentWarning)
                    }
                }
            }

            // Widget
            renderWidget(field: field, parameter: parameter, value: value)

            // Description
            if let description = parameter?.description {
                Text(description)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }

    /// Render the appropriate widget for a field
    @ViewBuilder
    static func renderWidget(
        field: ToolFormField,
        parameter: ToolParameterV2?,
        value: Binding<Any?>
    ) -> some View {
        switch field.widget {
        case .textField:
            TextFieldWidget(
                placeholder: field.placeholder ?? "",
                value: stringBinding(from: value)
            )

        case .textarea:
            TextAreaWidget(
                placeholder: field.placeholder ?? "",
                rows: field.rows ?? 3,
                value: stringBinding(from: value)
            )

        case .slider:
            SliderWidget(
                min: field.min ?? parameter?.minimum ?? 0,
                max: field.max ?? parameter?.maximum ?? 1,
                step: field.step ?? 0.1,
                value: doubleBinding(from: value)
            )

        case .segmented:
            SegmentedWidget(
                options: field.options ?? enumOptions(from: parameter),
                value: stringBinding(from: value)
            )

        case .tagInput:
            TagInputWidget(
                placeholder: field.placeholder ?? "Add tag...",
                value: stringBinding(from: value)
            )

        case .toggle:
            ToggleWidget(
                value: boolBinding(from: value)
            )

        case .picker:
            PickerWidget(
                options: field.options ?? enumOptions(from: parameter),
                value: stringBinding(from: value)
            )

        case .datePicker:
            DatePickerWidget(
                value: dateBinding(from: value)
            )

        case .stepper:
            StepperWidget(
                min: Int(field.min ?? parameter?.minimum ?? 0),
                max: Int(field.max ?? parameter?.maximum ?? 100),
                value: intBinding(from: value)
            )

        case .colorPicker:
            ColorPickerWidget(
                value: stringBinding(from: value)
            )
        }
    }

    // MARK: - Result Display Rendering

    /// Render result display from tool UI config
    /// - Parameters:
    ///   - config: The result display configuration
    ///   - result: The tool execution result data
    @ViewBuilder
    static func renderResultDisplay(
        config: ToolResultDisplayConfig,
        result: [String: Any]
    ) -> some View {
        let style = config.style ?? .card

        switch style {
        case .card:
            VStack(alignment: .leading, spacing: 12) {
                if let sections = config.sections {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        renderResultSection(section: section, data: result)
                    }
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(12)

        case .inline:
            VStack(alignment: .leading, spacing: 8) {
                if let sections = config.sections {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        renderResultSection(section: section, data: result)
                    }
                }
            }

        case .modal, .notification:
            VStack(alignment: .leading, spacing: 12) {
                if let sections = config.sections {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        renderResultSection(section: section, data: result)
                    }
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(12)
            .shadow(color: AppColors.shadow, radius: 10, x: 0, y: 4)
        }
    }

    /// Render a single result section
    /// Uses AnyView to avoid complex opaque type inference from switch statement
    static func renderResultSection(
        section: ResultSection,
        data: [String: Any]
    ) -> AnyView {
        switch section.type {
        case .header:
            return AnyView(
                HStack(spacing: 8) {
                    if let icon = section.icon {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.signalLichen)
                    }
                    Text(resolveTemplate(section.title ?? "", with: data))
                        .font(AppTypography.titleSmall())
                        .foregroundColor(AppColors.textPrimary)
                }
            )

        case .text:
            return AnyView(
                Text(resolveTemplate(section.source ?? "", with: data))
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
            )

        case .code:
            return AnyView(
                Text(resolveTemplate(section.source ?? "", with: data))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(12)
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(8)
            )

        case .list:
            if let items = section.items {
                return AnyView(
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(AppColors.textTertiary)
                                    .frame(width: 4, height: 4)
                                renderResultSection(section: item, data: data)
                            }
                        }
                    }
                )
            }
            return AnyView(EmptyView())

        case .keyValue:
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    if let title = section.title {
                        Text(title)
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    if let items = section.items {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Text(item.title ?? "")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                                Spacer()
                                Text(resolveTemplate(item.source ?? "", with: data))
                                    .font(AppTypography.bodySmall(.medium))
                                    .foregroundColor(AppColors.textPrimary)
                            }
                        }
                    }
                }
            )

        case .divider:
            return AnyView(
                Divider()
                    .background(AppColors.divider)
            )

        case .spacer:
            return AnyView(
                Spacer()
                    .frame(height: 8)
            )

        case .image:
            if let source = section.source,
               let url = URL(string: resolveTemplate(source, with: data)) {
                return AnyView(
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: 200)
                )
            }
            return AnyView(EmptyView())

        case .link:
            if let source = section.source {
                let urlString = resolveTemplate(source, with: data)
                if let url = URL(string: urlString) {
                    return AnyView(
                        Link(destination: url) {
                            HStack {
                                Text(section.title ?? urlString)
                                    .font(AppTypography.bodyMedium())
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(AppColors.signalMercury)
                        }
                    )
                }
            }
            return AnyView(EmptyView())

        case .badge:
            return AnyView(
                Text(resolveTemplate(section.source ?? "", with: data))
                    .font(AppTypography.labelSmall())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.signalCopper)
                    .cornerRadius(4)
            )

        case .progress:
            if let source = section.source,
               let value = Double(resolveTemplate(source, with: data)) {
                return AnyView(
                    ProgressView(value: value)
                        .progressViewStyle(LinearProgressViewStyle(tint: AppColors.signalLichen))
                )
            }
            return AnyView(EmptyView())
        }
    }

    // MARK: - Template Resolution

    /// Resolve template variables like {{param}} with actual values
    static func resolveTemplate(_ template: String, with data: [String: Any]) -> String {
        var result = template

        // Match {{variable}} or {{variable.nested}}
        let pattern = #"\{\{([^}]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }

        let matches = regex.matches(
            in: template,
            range: NSRange(template.startIndex..., in: template)
        )

        for match in matches.reversed() {
            guard let range = Range(match.range, in: template),
                  let keyRange = Range(match.range(at: 1), in: template) else {
                continue
            }

            let key = String(template[keyRange])
            let value = resolveKeyPath(key, in: data)
            result = result.replacingCharacters(in: range, with: value)
        }

        return result
    }

    /// Resolve a dot-separated key path in data
    private static func resolveKeyPath(_ keyPath: String, in data: [String: Any]) -> String {
        let components = keyPath.split(separator: ".").map(String.init)
        var current: Any = data

        for component in components {
            if let dict = current as? [String: Any], let value = dict[component] {
                current = value
            } else {
                return ""
            }
        }

        return "\(current)"
    }

    // MARK: - Binding Helpers

    private static func bindingForField(_ param: String, in values: Binding<[String: Any]>) -> Binding<Any?> {
        Binding<Any?>(
            get: { values.wrappedValue[param] },
            set: { values.wrappedValue[param] = $0 as Any }
        )
    }

    private static func stringBinding(from value: Binding<Any?>) -> Binding<String> {
        Binding<String>(
            get: { value.wrappedValue as? String ?? "" },
            set: { value.wrappedValue = $0 }
        )
    }

    private static func doubleBinding(from value: Binding<Any?>) -> Binding<Double> {
        Binding<Double>(
            get: { (value.wrappedValue as? Double) ?? (value.wrappedValue as? NSNumber)?.doubleValue ?? 0 },
            set: { value.wrappedValue = $0 }
        )
    }

    private static func intBinding(from value: Binding<Any?>) -> Binding<Int> {
        Binding<Int>(
            get: { (value.wrappedValue as? Int) ?? (value.wrappedValue as? NSNumber)?.intValue ?? 0 },
            set: { value.wrappedValue = $0 }
        )
    }

    private static func boolBinding(from value: Binding<Any?>) -> Binding<Bool> {
        Binding<Bool>(
            get: { (value.wrappedValue as? Bool) ?? false },
            set: { value.wrappedValue = $0 }
        )
    }

    private static func dateBinding(from value: Binding<Any?>) -> Binding<Date> {
        Binding<Date>(
            get: { (value.wrappedValue as? Date) ?? Date() },
            set: { value.wrappedValue = $0 }
        )
    }

    /// Generate options from enum parameter
    private static func enumOptions(from parameter: ToolParameterV2?) -> [WidgetOption] {
        guard let enumValues = parameter?.enum else { return [] }

        return enumValues.map { value in
            WidgetOption(
                value: value,
                label: parameter?.enumDescriptions?[value] ?? value.capitalized,
                icon: nil
            )
        }
    }
}

// MARK: - Widget Components

/// Text field widget
private struct TextFieldWidget: View {
    let placeholder: String
    @Binding var value: String

    var body: some View {
        TextField(placeholder, text: $value)
            .textFieldStyle(.plain)
            .padding(12)
            .background(AppColors.substrateTertiary)
            .cornerRadius(8)
            .foregroundColor(AppColors.textPrimary)
    }
}

/// Text area widget
private struct TextAreaWidget: View {
    let placeholder: String
    let rows: Int
    @Binding var value: String

    var body: some View {
        TextEditor(text: $value)
            .font(AppTypography.bodyMedium())
            .foregroundColor(AppColors.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: CGFloat(rows * 24))
            .background(AppColors.substrateTertiary)
            .cornerRadius(8)
            .overlay(alignment: .topLeading) {
                if value.isEmpty {
                    Text(placeholder)
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Slider widget
private struct SliderWidget: View {
    let min: Double
    let max: Double
    let step: Double
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: $value, in: min...max, step: step)
                .tint(AppColors.signalMercury)

            Text(String(format: "%.1f", value))
                .font(AppTypography.bodyMedium(.medium))
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 40)
        }
    }
}

/// Segmented control widget
private struct SegmentedWidget: View {
    let options: [WidgetOption]
    @Binding var value: String

    var body: some View {
        Picker("", selection: $value) {
            ForEach(options, id: \.value) { option in
                HStack(spacing: 4) {
                    if let icon = option.icon {
                        Image(systemName: icon)
                    }
                    Text(option.label)
                }
                .tag(option.value)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// Tag input widget
private struct TagInputWidget: View {
    let placeholder: String
    @Binding var value: String
    @State private var currentTag = ""

    private var tags: [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tag display
            if !tags.isEmpty {
                ToolUIFlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(tag: tag) {
                            removeTag(tag)
                        }
                    }
                }
            }

            // Input field
            HStack {
                TextField(placeholder, text: $currentTag)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        addTag()
                    }

                Button(action: addTag) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(AppColors.signalMercury)
                }
                .buttonStyle(.plain)
                .disabled(currentTag.isEmpty)
            }
            .padding(12)
            .background(AppColors.substrateTertiary)
            .cornerRadius(8)
        }
    }

    private func addTag() {
        guard !currentTag.isEmpty else { return }
        let newTag = currentTag.trimmingCharacters(in: .whitespaces)
        if !tags.contains(newTag) {
            value = (tags + [newTag]).joined(separator: ", ")
        }
        currentTag = ""
    }

    private func removeTag(_ tag: String) {
        value = tags.filter { $0 != tag }.joined(separator: ", ")
    }
}

/// Tag chip component
private struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(AppTypography.labelSmall())

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(AppColors.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppColors.signalMercury.opacity(0.2))
        .cornerRadius(4)
    }
}

/// Flow layout for tags in tool UI
private struct ToolUIFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let maxX = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxX && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

/// Toggle widget
private struct ToggleWidget: View {
    @Binding var value: Bool

    var body: some View {
        Toggle("", isOn: $value)
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()
    }
}

/// Picker widget
private struct PickerWidget: View {
    let options: [WidgetOption]
    @Binding var value: String

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    value = option.value
                } label: {
                    HStack {
                        if let icon = option.icon {
                            Image(systemName: icon)
                        }
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack {
                Text(options.first { $0.value == value }?.label ?? "Select...")
                    .foregroundColor(value.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(12)
            .background(AppColors.substrateTertiary)
            .cornerRadius(8)
        }
    }
}

/// Date picker widget
private struct DatePickerWidget: View {
    @Binding var value: Date

    var body: some View {
        DatePicker("", selection: $value, displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
            .tint(AppColors.signalMercury)
    }
}

/// Stepper widget
private struct StepperWidget: View {
    let min: Int
    let max: Int
    @Binding var value: Int

    var body: some View {
        HStack {
            Stepper("", value: $value, in: min...max)
                .labelsHidden()

            Text("\(value)")
                .font(AppTypography.bodyMedium(.medium))
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 40)
        }
    }
}

/// Color picker widget
private struct ColorPickerWidget: View {
    @Binding var value: String
    @State private var color: Color = .blue

    var body: some View {
        ColorPicker("", selection: $color)
            .labelsHidden()
            .onChange(of: color) { _, newColor in
                value = newColor.description
            }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            // Sample form
            ToolUIRenderer.renderInputForm(
                config: ToolInputFormConfig(
                    fields: [
                        ToolFormField(
                            param: "type",
                            widget: .segmented,
                            label: "Type",
                            placeholder: nil,
                            rows: nil,
                            min: nil,
                            max: nil,
                            step: nil,
                            options: [
                                WidgetOption(value: "a", label: "Option A", icon: "star"),
                                WidgetOption(value: "b", label: "Option B", icon: "heart")
                            ],
                            showIf: nil
                        ),
                        ToolFormField(
                            param: "content",
                            widget: .textarea,
                            label: "Content",
                            placeholder: "Enter content...",
                            rows: 3,
                            min: nil,
                            max: nil,
                            step: nil,
                            options: nil,
                            showIf: nil
                        )
                    ],
                    layout: .vertical,
                    submitLabel: "Save"
                ),
                parameters: nil,
                values: .constant([:]),
                onSubmit: {}
            )

            // Sample result
            ToolUIRenderer.renderResultDisplay(
                config: ToolResultDisplayConfig(
                    sections: [
                        ResultSection(type: .header, title: "Success", source: nil, icon: "checkmark.circle.fill", style: nil, items: nil),
                        ResultSection(type: .text, title: nil, source: "Operation completed", icon: nil, style: nil, items: nil)
                    ],
                    style: .card
                ),
                result: [:]
            )
        }
        .padding()
    }
    .background(AppColors.substratePrimary)
}
