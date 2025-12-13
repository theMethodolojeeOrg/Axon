//
//  PlatformImage.swift
//  Axon
//
//  Cross-platform image helpers (iOS UIKit / macOS AppKit)
//

import Foundation

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage

public enum PlatformImageCodec {
    /// Decode from raw bytes.
    public static func image(from data: Data) -> PlatformImage? {
        UIImage(data: data)
    }

    /// Encode to JPEG.
    public static func jpegData(from image: PlatformImage, compressionQuality: CGFloat) -> Data? {
        image.jpegData(compressionQuality: compressionQuality)
    }
}

#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage

public enum PlatformImageCodec {
    /// Decode from raw bytes.
    public static func image(from data: Data) -> PlatformImage? {
        NSImage(data: data)
    }

    /// Encode to JPEG.
    public static func jpegData(from image: PlatformImage, compressionQuality: CGFloat) -> Data? {
        // Convert NSImage -> NSBitmapImageRep
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        // NSBitmapImageRep uses a 0.0-1.0 float quality
        let quality = max(0.0, min(1.0, Double(compressionQuality)))
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

#else
// If a new platform is added later, fail gracefully.
public typealias PlatformImage = Never

public enum PlatformImageCodec {
    public static func image(from data: Data) -> PlatformImage? { nil }
    public static func jpegData(from image: PlatformImage, compressionQuality: CGFloat) -> Data? { nil }
}
#endif
