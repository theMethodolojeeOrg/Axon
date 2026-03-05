//
//  BridgeQRCodeGenerator.swift
//  Axon
//
//  QR code generation for Bridge connection sharing.
//  Produces payloads compatible with BridgeConnectionQRParser.
//

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum BridgeQRCodeGenerator {

    /// Builds a QR payload string matching the format expected by `BridgeConnectionQRParser`.
    /// Format: `ws://host:port` or `wss://host:port?pairingToken=TOKEN`
    static func generatePayload(
        host: String,
        port: UInt16,
        tlsEnabled: Bool,
        pairingToken: String? = nil
    ) -> String {
        let base = BridgeNetworkUtils.buildWebSocketURL(host: host, port: port, tlsEnabled: tlsEnabled)
        if let token = pairingToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            return "\(base)?pairingToken=\(encoded)"
        }
        return base
    }

    #if os(iOS)
    /// Generates a QR code UIImage from a payload string.
    static func generateImage(from payload: String, size: CGFloat = 200) -> UIImage? {
        guard let ciImage = generateCIImage(from: payload, size: size) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    #elseif os(macOS)
    /// Generates a QR code NSImage from a payload string.
    static func generateImage(from payload: String, size: CGFloat = 200) -> NSImage? {
        guard let ciImage = generateCIImage(from: payload, size: size) else { return nil }
        let rep = NSCIImageRep(ciImage: ciImage)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
    #endif

    // MARK: - Private

    private static func generateCIImage(from payload: String, size: CGFloat) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale to requested size
        let scaleX = size / outputImage.extent.size.width
        let scaleY = size / outputImage.extent.size.height
        return outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
}
