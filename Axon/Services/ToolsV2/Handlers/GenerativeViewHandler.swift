//
//  GenerativeViewHandler.swift
//  Axon
//
//  Tool handler letting AI agents create and edit USE-format generative
//  views (rendered by USEBridge, viewable from Create > Views).
//
//  Tools served (manifest.tool.id):
//    get_view_catalog — component/action reference for authoring specs
//    create_view      — validate + save a new USE view
//    update_view      — whole-document replace or targeted patch ops
//    get_view         — read a stored view's spec
//    list_views       — enumerate stored views
//    delete_view      — remove a user-created view
//

import Foundation

@MainActor
final class GenerativeViewHandler: BaseToolHandlerV2 {

    init() {
        super.init(handlerId: "generative_view")
    }

    override func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id

        switch toolId {
        case "get_view_catalog":
            return getViewCatalog(toolId: toolId, inputs: inputs)
        case "create_view":
            return await createView(toolId: toolId, inputs: inputs)
        case "update_view":
            return await updateView(toolId: toolId, inputs: inputs)
        case "get_view":
            return getView(toolId: toolId, inputs: inputs)
        case "list_views":
            return listViews(toolId: toolId, inputs: inputs)
        case "delete_view":
            return deleteView(toolId: toolId, inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown generative view tool: \(toolId)")
        }
    }

    // MARK: - get_view_catalog

    private func getViewCatalog(toolId: String, inputs: [String: Any]) -> ToolResultV2 {
        let filter = stringValue("filter", from: inputs)
        let catalogJSON = UseComponentCatalogService.shared.compactCatalogJSON(filter: filter)
        return successResult(
            toolId: toolId,
            output: catalogJSON,
            structured: ["catalog": catalogJSON]
        )
    }

    // MARK: - create_view

    private func createView(toolId: String, inputs: [String: Any]) async -> ToolResultV2 {
        guard let name = stringValue("name", from: inputs), !name.isEmpty else {
            return failureResult(toolId: toolId, error: "Missing required parameter: name")
        }
        guard let document = documentValue("document", from: inputs) else {
            return failureResult(toolId: toolId, error: "Missing or malformed 'document'. Pass the USE spec as a JSON object like {\"component\": \"vstack\", \"props\": {...}, \"children\": [...]}.")
        }

        let validation = UseViewValidator.validate(document)
        guard validation.isValid else {
            return failureResult(toolId: toolId, error: validationFailureMessage(validation))
        }

        do {
            let view = try GenerativeViewStorageService.shared.createUseView(
                name: name,
                document: USEDocument.from(document)
            )
            await GenerativeViewStorageService.shared.updateThumbnail(for: view.id)

            var output = "Created view '\(name)' (id: \(view.id.uuidString)). It is now visible in Create > Views."
            if !validation.warnings.isEmpty {
                output += "\nWarnings:\n" + validation.warnings.joined(separator: "\n")
            }
            return successResult(
                toolId: toolId,
                output: output,
                structured: ["id": view.id.uuidString, "name": name]
            )
        } catch {
            return failureResult(toolId: toolId, error: "Failed to save view: \(error.localizedDescription)")
        }
    }

    // MARK: - update_view

    private func updateView(toolId: String, inputs: [String: Any]) async -> ToolResultV2 {
        guard let view = lookupView(from: inputs) else {
            return failureResult(toolId: toolId, error: "Missing or unknown view 'id'. Call list_views to see stored views.")
        }
        guard view.format == .useV1 else {
            return failureResult(toolId: toolId, error: "View '\(view.name)' is a legacy-format view and cannot be edited with this tool.")
        }
        guard view.source == .userCreated else {
            return failureResult(toolId: toolId, error: "View '\(view.name)' is a read-only bundled template. Use create_view to make an editable copy.")
        }

        let newDocument: [String: Any]
        if let document = documentValue("document", from: inputs) {
            newDocument = document
        } else if let patches = patchesValue("patches", from: inputs) {
            guard let current = view.useDocument?.asDictionary() else {
                return failureResult(toolId: toolId, error: "View '\(view.name)' has no stored document to patch.")
            }
            do {
                newDocument = try UseViewPatchApplier.apply(patches, to: current)
            } catch {
                return failureResult(toolId: toolId, error: "Patch failed: \(error.localizedDescription)")
            }
        } else {
            return failureResult(toolId: toolId, error: "Provide either 'document' (full replacement) or 'patches' (array of patch ops).")
        }

        let validation = UseViewValidator.validate(newDocument)
        guard validation.isValid else {
            return failureResult(toolId: toolId, error: validationFailureMessage(validation))
        }

        do {
            var updated = view
            updated.update(document: USEDocument.from(newDocument))
            if let newName = stringValue("name", from: inputs), !newName.isEmpty {
                updated.rename(to: newName)
            }
            try GenerativeViewStorageService.shared.saveUserView(updated)
            await GenerativeViewStorageService.shared.updateThumbnail(for: updated.id)

            var output = "Updated view '\(updated.name)' (id: \(updated.id.uuidString))."
            if !validation.warnings.isEmpty {
                output += "\nWarnings:\n" + validation.warnings.joined(separator: "\n")
            }
            return successResult(
                toolId: toolId,
                output: output,
                structured: ["id": updated.id.uuidString, "name": updated.name]
            )
        } catch {
            return failureResult(toolId: toolId, error: "Failed to save view: \(error.localizedDescription)")
        }
    }

    // MARK: - get_view

    private func getView(toolId: String, inputs: [String: Any]) -> ToolResultV2 {
        guard let view = lookupView(from: inputs) else {
            return failureResult(toolId: toolId, error: "Missing or unknown view 'id'. Call list_views to see stored views.")
        }

        switch view.format {
        case .useV1:
            guard let document = view.useDocument?.asDictionary(),
                  let data = try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else {
                return failureResult(toolId: toolId, error: "View '\(view.name)' has no readable document.")
            }
            return successResult(
                toolId: toolId,
                output: json,
                structured: ["id": view.id.uuidString, "name": view.name, "format": "useV1"]
            )
        case .legacy:
            return failureResult(toolId: toolId, error: "View '\(view.name)' is a legacy-format view; its definition is not USE JSON.")
        }
    }

    // MARK: - list_views

    private func listViews(toolId: String, inputs: [String: Any]) -> ToolResultV2 {
        let formatFilter = stringValue("format", from: inputs)?.lowercased() ?? "all"

        var views = GenerativeViewStorageService.shared.allViews
        switch formatFilter {
        case "use", "usev1":
            views = views.filter { $0.format == .useV1 }
        case "legacy":
            views = views.filter { $0.format == .legacy }
        default:
            break
        }

        if views.isEmpty {
            return successResult(toolId: toolId, output: "No stored views match.", structured: ["views": []])
        }

        let formatter = ISO8601DateFormatter()
        let entries: [[String: Any]] = views.map { view in
            [
                "id": view.id.uuidString,
                "name": view.name,
                "format": view.format.rawValue,
                "source": view.source.rawValue,
                "updatedAt": formatter.string(from: view.updatedAt)
            ]
        }

        let lines = views.map { view in
            "- \(view.name) [\(view.format.rawValue), \(view.source.rawValue)] id: \(view.id.uuidString)"
        }
        return successResult(
            toolId: toolId,
            output: "\(views.count) view(s):\n" + lines.joined(separator: "\n"),
            structured: ["views": entries]
        )
    }

    // MARK: - delete_view

    private func deleteView(toolId: String, inputs: [String: Any]) -> ToolResultV2 {
        guard let view = lookupView(from: inputs) else {
            return failureResult(toolId: toolId, error: "Missing or unknown view 'id'. Call list_views to see stored views.")
        }
        guard view.source == .userCreated else {
            return failureResult(toolId: toolId, error: "View '\(view.name)' is a bundled template and cannot be deleted.")
        }

        do {
            try GenerativeViewStorageService.shared.deleteUserView(id: view.id)
            return successResult(
                toolId: toolId,
                output: "Deleted view '\(view.name)' (id: \(view.id.uuidString)).",
                structured: ["id": view.id.uuidString]
            )
        } catch {
            return failureResult(toolId: toolId, error: "Failed to delete view: \(error.localizedDescription)")
        }
    }

    // MARK: - Input Helpers

    private func lookupView(from inputs: [String: Any]) -> GenerativeViewDefinition? {
        guard let idString = stringValue("id", from: inputs),
              let id = UUID(uuidString: idString) else { return nil }
        return GenerativeViewStorageService.shared.view(for: id)
    }

    /// Accept a USE document as a nested JSON object or a JSON string.
    private func documentValue(_ key: String, from inputs: [String: Any]) -> [String: Any]? {
        if let dict = inputs[key] as? [String: Any] {
            return dict
        }
        if let string = inputs[key] as? String,
           let data = string.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return nil
    }

    /// Accept patches as a nested JSON array or a JSON string.
    private func patchesValue(_ key: String, from inputs: [String: Any]) -> [[String: Any]]? {
        if let array = inputs[key] as? [[String: Any]] {
            return array
        }
        if let array = inputs[key] as? [Any] {
            let dicts = array.compactMap { $0 as? [String: Any] }
            return dicts.count == array.count ? dicts : nil
        }
        if let string = inputs[key] as? String,
           let data = string.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array
        }
        return nil
    }

    private func validationFailureMessage(_ validation: UseViewValidator.ValidationResult) -> String {
        var message = "View document failed validation:\n" + validation.errors.joined(separator: "\n")
        if !validation.warnings.isEmpty {
            message += "\nWarnings:\n" + validation.warnings.joined(separator: "\n")
        }
        message += "\nCall get_view_catalog for the list of valid components and actions."
        return message
    }
}
