//
//  MacSharePicker.swift
//  Axon
//
//  Minimal NSSharingServicePicker wrapper for macOS.
//

import SwiftUI

#if os(macOS)
import AppKit

struct MacSharePicker: NSViewRepresentable {
    let items: [Any]

    /// The picker needs an anchor view to attach to.
    /// We show it on update when `items` changes.
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !items.isEmpty else { return }

        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
        }
    }
}
#endif
