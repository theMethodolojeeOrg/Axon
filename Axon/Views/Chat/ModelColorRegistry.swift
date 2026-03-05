import SwiftUI
import Combine

final class ModelColorRegistry {
    static let shared = ModelColorRegistry()

    private let userDefaultsKey = "model_color_registry_v1"
    
    // Brand colors reserved (hex uppercase, without #)
    // Anthropic brand color
    private let anthropicHex = "0065FF" // Blue
    // OpenAI brand color
    private let openAIHex = "10A37F"    // Greenish
    // Gemini is a gradient, so no hex reserved
    
    // Palette of muted hex colors (uppercase, without #)
    // Muted colors chosen to be visually distinct and not too bright
    private let palette: [String] = [
        "8B5CF6", // violet-500 muted
        "EC4899", // pink-500 muted
        "F97316", // orange-500 muted
        "22D3EE", // cyan-400 muted
        "EAB308", // yellow-400 muted
        "4ADE80", // green-400 muted
        "60A5FA", // blue-400 muted
        "F472B6", // pink-400 muted
        "A78BFA", // purple-400 muted
        "FBBF24", // amber-400 muted
        "34D399", // emerald-400 muted
        "3B82F6", // blue-500 muted
        "F87171", // red-400 muted
        "F59E0B", // amber-500 muted
        "22C55E", // green-500 muted
        "818CF8", // indigo-400 muted
        "D8B4FE", // purple-300 muted
        "FCD34D", // yellow-300 muted
        "6EE7B7", // teal-300 muted
        "60A5FA"  // sky-400 muted (repeat for some variety)
    ]
    
    // Stored assignments: key -> hex (uppercase without #)
    // loaded from UserDefaults
    private var assignments: [String: String]
    
    private var takenColors: Set<String> {
        var set = Set(assignments.values.map { $0.uppercased() })
        set.insert(anthropicHex)
        set.insert(openAIHex)
        return set
    }
    
    private let lock = NSLock()
    
    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] {
            var clean: [String: String] = [:]
            for (k, v) in saved {
                let hex = v.uppercased()
                if ModelColorRegistry.isValidHex(hex) {
                    clean[k] = hex
                }
            }
            self.assignments = clean
        } else {
            self.assignments = [:]
        }
    }
    
    /// Returns a SwiftUI Color for the provided key. If missing, assigns and persists a new color.
    func color(forKey key: String) -> Color {
        lock.lock()
        defer { lock.unlock() }
        
        if let hex = assignments[key]?.uppercased(), ModelColorRegistry.isValidHex(hex) {
            return ModelColorRegistry.color(fromHex: hex)
        }
        
        // Assign new color
        let newHex = assignNewColor(forKey: key)
        return ModelColorRegistry.color(fromHex: newHex)
    }
    
    /// Returns the hex string (uppercase without #) for the provided key if assigned, else assigns a new one.
    func hex(forKey key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        
        if let hex = assignments[key]?.uppercased(), ModelColorRegistry.isValidHex(hex) {
            return hex
        }
        
        // Assign new color
        let newHex = assignNewColor(forKey: key)
        return newHex
    }
    
    /// Overrides the hex color for the given key, if hex is valid and not used by another key or reserved.
    /// If invalid hex or conflicts, override is ignored.
    func override(key: String, with hex: String) {
        let hexUp = hex.uppercased()
        guard ModelColorRegistry.isValidHex(hexUp) else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        // Check conflicts
        if takenColors.contains(hexUp) {
            // If this hex is already assigned to this key, allow override (no op)
            if assignments[key]?.uppercased() == hexUp {
                return
            }
            // Otherwise reject override
            return
        }
        assignments[key] = hexUp
        persist()
    }
    
    // MARK: - Private
    
    private func assignNewColor(forKey key: String) -> String {
        // Ensure we don't assign a hex already taken
        
        // Try palette first
        for candidate in palette {
            if !takenColors.contains(candidate) {
                assignments[key] = candidate
                persist()
                return candidate
            }
        }
        
        // Palette exhausted - generate random muted colors
        for _ in 0..<100 {
            let candidate = Self.randomMutedHex()
            if !takenColors.contains(candidate) {
                assignments[key] = candidate
                persist()
                return candidate
            }
        }
        
        // Fallback gray
        let fallback = "888888"
        assignments[key] = fallback
        persist()
        return fallback
    }
    
    private func persist() {
        UserDefaults.standard.set(assignments, forKey: userDefaultsKey)
    }
    
    // MARK: - Helpers
    
    /// Validates hex color string of format RRGGBB (case insensitive)
    static func isValidHex(_ hex: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: "^[0-9A-Fa-f]{6}$")
        let range = NSRange(location: 0, length: hex.utf16.count)
        return regex.firstMatch(in: hex, options: [], range: range) != nil
    }
    
    /// Converts hex string (RRGGBB) to SwiftUI Color
    static func color(fromHex hex: String) -> Color {
        let hexUp = hex.uppercased()
        guard hexUp.count == 6 else { return Color.gray }
        
        let rStr = hexUp.prefix(2)
        let gStr = hexUp.dropFirst(2).prefix(2)
        let bStr = hexUp.dropFirst(4).prefix(2)
        
        let r = UInt8(rStr, radix: 16) ?? 136
        let g = UInt8(gStr, radix: 16) ?? 136
        let b = UInt8(bStr, radix: 16) ?? 136
        
        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1.0
        )
    }
    
    /// Generates a random muted hex color string (RRGGBB uppercase)
    /// Muted means saturation and brightness are limited
    static func randomMutedHex() -> String {
        // Generate in HSB space with:
        // Hue: 0...360 random
        // Saturation: 0.3...0.6 (muted)
        // Brightness: 0.4...0.7 (not too bright)
        let hue = Double.random(in: 0...360)
        let saturation = Double.random(in: 0.3...0.6)
        let brightness = Double.random(in: 0.4...0.7)
        
        // Convert HSB to RGB
        let rgb = Self.hsbToRgb(hue: hue, saturation: saturation, brightness: brightness)
        
        // Format to hex
        return String(format: "%02X%02X%02X", rgb.r, rgb.g, rgb.b)
    }
    
    /// Converts HSB to RGB UInt8 tuple
    /// hue: 0-360, saturation and brightness: 0-1
    private static func hsbToRgb(hue: Double, saturation: Double, brightness: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        let h = hue / 60
        let c = brightness * saturation
        let x = c * (1 - abs(fmod(h, 2) - 1))
        let m = brightness - c
        
        var r1 = 0.0, g1 = 0.0, b1 = 0.0
        
        switch h {
        case 0..<1:
            r1 = c; g1 = x; b1 = 0
        case 1..<2:
            r1 = x; g1 = c; b1 = 0
        case 2..<3:
            r1 = 0; g1 = c; b1 = x
        case 3..<4:
            r1 = 0; g1 = x; b1 = c
        case 4..<5:
            r1 = x; g1 = 0; b1 = c
        case 5..<6:
            r1 = c; g1 = 0; b1 = x
        default:
            r1 = 0; g1 = 0; b1 = 0
        }
        
        let r = UInt8(max(0, min(255, Int((r1 + m) * 255))))
        let g = UInt8(max(0, min(255, Int((g1 + m) * 255))))
        let b = UInt8(max(0, min(255, Int((b1 + m) * 255))))
        
        return (r, g, b)
    }
}
