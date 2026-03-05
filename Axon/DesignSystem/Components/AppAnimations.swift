//
//  AppAnimations.swift
//  Axon
//
//  Design System Animations - Minimal motion, 200ms standard
//

import SwiftUI

struct AppAnimations {

    // MARK: - Standard Durations

    /// Standard animation duration - 200ms
    static let standard: Double = 0.2

    /// Fast animation - 100ms
    static let fast: Double = 0.1

    /// Slow animation - 300ms
    static let slow: Double = 0.3

    /// Very slow for complex transitions - 400ms
    static let verySlow: Double = 0.4

    // MARK: - Easing Curves

    /// Standard easing curve
    static let standardEasing = Animation.easeInOut(duration: standard)

    /// Fast easing
    static let fastEasing = Animation.easeInOut(duration: fast)

    /// Slow easing
    static let slowEasing = Animation.easeInOut(duration: slow)

    /// Spring animation for natural motion
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Gentle spring
    static let springGentle = Animation.spring(response: 0.4, dampingFraction: 0.8)

    // MARK: - Transition Animations

    /// Fade transition
    static let fade = AnyTransition.opacity.animation(standardEasing)

    /// Slide from bottom
    static let slideFromBottom = AnyTransition.move(edge: .bottom).combined(with: .opacity).animation(standardEasing)

    /// Slide from top
    static let slideFromTop = AnyTransition.move(edge: .top).combined(with: .opacity).animation(standardEasing)

    /// Scale transition
    static let scale = AnyTransition.scale.combined(with: .opacity).animation(standardEasing)
}
