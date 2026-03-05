//
//  ActivityView.swift
//  Axon
//
//  Minimal UIActivityViewController wrapper for iOS share/export.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
