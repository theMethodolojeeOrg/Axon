//
//  AppLockView.swift
//  Axon
//
//  App lock screen with biometric/passcode authentication
//  Styled to match the launch screen aesthetic
//

import SwiftUI
import Combine

struct AppLockView: View {
    @Binding var isUnlocked: Bool

    var body: some View {
        GeometryReader { geometry in
            AppLockContent(screenSize: geometry.size, isUnlocked: $isUnlocked)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Lock Screen Content

private struct AppLockContent: View {
    @StateObject private var biometricService = BiometricAuthService.shared
    @StateObject private var physicsEngine: LockScreenBubbleEngine
    @Binding var isUnlocked: Bool

    @State private var isAuthenticating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var animationTime: Double = 0
    @State private var timer: Timer?
    @State private var viewDidAppear = false

    // Animation states
    @State private var screenOpacity: Double = 0
    @State private var glassOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.9
    @State private var lockIconScale: CGFloat = 0.8
    @State private var bubblesStarted: Bool = false

    private let screenSize: CGSize

    init(screenSize: CGSize, isUnlocked: Binding<Bool>) {
        self._physicsEngine = StateObject(wrappedValue: LockScreenBubbleEngine(
            screenWidth: screenSize.width,
            screenHeight: screenSize.height
        ))
        self.screenSize = screenSize
        self._isUnlocked = isUnlocked
    }

    var body: some View {
        ZStack {
            // Background - signalMercuryDark (matches launch screen)
            AppColors.signalMercuryDark
                .ignoresSafeArea()

            // Layer 1: Bubbles (underneath everything)
            ZStack {
                ForEach(physicsEngine.bubbles) { bubble in
                    if bubble.hasLaunched && bubblesStarted {
                        Image("Bubble")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: bubble.size, height: bubble.size)
                            .opacity(0.08 + Double(bubble.zDepth) * 0.15)
                            .position(bubble.position)
                            .scaleEffect(1.0 + sin(animationTime * 2 + Double(bubble.id.hashValue)) * 0.03)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: bubble.position)
                    }
                }
            }

            // Layer 2: Main content
            VStack(spacing: 0) {
                Spacer()

                // Logo
                Image("AxonLight")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 180, height: 180)
                    .opacity(0.9)
                    .scaleEffect(logoScale)

                Spacer()
                    .frame(height: 60)

                // Lock indicator and auth button
                VStack(spacing: 24) {
                    // Biometric/Lock icon button
                    Button(action: authenticate) {
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 90, height: 90)

                            // Inner circle with glass effect
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AppColors.signalMercury.opacity(0.3),
                                            AppColors.signalMercuryDark.opacity(0.5)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 84, height: 84)

                            // Icon
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                            } else {
                                Image(systemName: biometricService.biometricType.icon)
                                    .font(.system(size: 36, weight: .light))
                                    .foregroundColor(.white)
                                    .scaleEffect(lockIconScale)
                            }
                        }
                    }
                    .disabled(isAuthenticating)
                    .scaleEffect(lockIconScale)

                    // Unlock text
                    Text(unlockButtonText)
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.9))

                    // Error message
                    if showError {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(AppColors.signalHematite)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }

                Spacer()

                // Bottom info
                VStack(spacing: 8) {
                    if let deviceInfo = DeviceIdentity.shared.getDeviceInfo() {
                        Text("Device: \(deviceInfo.shortId)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Text("Tap to unlock")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .italic()
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom, 40)
            }

            // Layer 3: Glass overlay (microscope slide effect)
            LockScreenGlassOverlay()
                .opacity(glassOpacity)
                .allowsHitTesting(false)
        }
        .opacity(screenOpacity)
        .onAppear {
            guard !viewDidAppear else { return }
            viewDidAppear = true
            startAnimations()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onChange(of: isUnlocked) { _, newValue in
            if !newValue {
                // Reset for next lock
                viewDidAppear = false
                screenOpacity = 0
                glassOpacity = 0
                logoScale = 0.9
                lockIconScale = 0.8
                bubblesStarted = false
            }
        }
    }

    private var unlockButtonText: String {
        if isAuthenticating {
            return "Authenticating..."
        }

        switch biometricService.biometricType {
        case .faceID:
            return "Unlock with Face ID"
        case .touchID:
            return "Unlock with Touch ID"
        case .opticID:
            return "Unlock with Optic ID"
        case .none:
            return "Unlock with Passcode"
        }
    }

    private func startAnimations() {
        // Fade in screen
        withAnimation(.easeIn(duration: 0.5)) {
            screenOpacity = 1.0
        }

        // Glass overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.4)) {
                glassOpacity = 0.5
            }
        }

        // Logo scale
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                logoScale = 1.0
                lockIconScale = 1.0
            }
        }

        // Start bubbles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            bubblesStarted = true

            timer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { _ in
                animationTime += 1/60.0
                physicsEngine.update(deltaTime: 1/60.0, currentTime: animationTime)
            }
        }

        // Auto-authenticate after animations
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !isUnlocked && !isAuthenticating {
                authenticate()
            }
        }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        showError = false

        // Pulse animation on auth
        withAnimation(.easeInOut(duration: 0.2)) {
            lockIconScale = 0.9
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                lockIconScale = 1.0
            }
        }

        Task {
            let result = await biometricService.authenticate(reason: "Unlock Axon to access your conversations")

            await MainActor.run {
                isAuthenticating = false

                switch result {
                case .success:
                    // Success animation then unlock
                    withAnimation(.easeOut(duration: 0.3)) {
                        screenOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isUnlocked = true
                    }

                case .cancelled:
                    break

                case .fallback:
                    break

                case .failed(let error):
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        showError = true
                    }
                    errorMessage = error.localizedDescription

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showError = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Lock Screen Glass Overlay

private struct LockScreenGlassOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base glass with tint
                RoundedRectangle(cornerRadius: 60)
                    .fill(AppColors.signalMercuryDark.opacity(0.3))
                    .frame(
                        width: geometry.size.width * 1.25,
                        height: geometry.size.height * 1.25
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Radial gradient for lighting
                RoundedRectangle(cornerRadius: 60)
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.15), location: 0.3),
                                .init(color: Color.white.opacity(0.08), location: 0.5),
                                .init(color: Color.white.opacity(0.03), location: 0.7),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            center: UnitPoint(x: 0.4, y: 0.4),
                            startRadius: 50,
                            endRadius: 500
                        )
                    )
                    .frame(
                        width: geometry.size.width * 1.25,
                        height: geometry.size.height * 1.25
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }
}

// MARK: - Lock Screen Bubble Engine

class LockScreenBubbleEngine: ObservableObject {
    @Published var bubbles: [LockBubble] = []

    private let screenWidth: CGFloat
    private let screenHeight: CGFloat
    private let maxBubbles = 12

    init(screenWidth: CGFloat, screenHeight: CGFloat) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight

        // Create initial bubbles
        for i in 0..<maxBubbles {
            let bubble = LockBubble(
                id: UUID(),
                position: randomEdgePosition(),
                size: CGFloat.random(in: 30...80),
                velocity: CGPoint(x: CGFloat.random(in: -15...15), y: CGFloat.random(in: -15...15)),
                zDepth: Float.random(in: 0.2...0.8),
                hasLaunched: false,
                launchTime: Double(i) * 0.4
            )
            bubbles.append(bubble)
        }
    }

    func update(deltaTime: Double, currentTime: Double) {
        for i in 0..<bubbles.count {
            // Launch bubbles over time
            if !bubbles[i].hasLaunched && currentTime >= bubbles[i].launchTime {
                bubbles[i].hasLaunched = true
            }

            guard bubbles[i].hasLaunched else { continue }

            // Update position with gentle drift
            bubbles[i].position.x += bubbles[i].velocity.x * CGFloat(deltaTime)
            bubbles[i].position.y += bubbles[i].velocity.y * CGFloat(deltaTime)

            // Wrap around edges
            if bubbles[i].position.x < -bubbles[i].size {
                bubbles[i].position.x = screenWidth + bubbles[i].size
            } else if bubbles[i].position.x > screenWidth + bubbles[i].size {
                bubbles[i].position.x = -bubbles[i].size
            }

            if bubbles[i].position.y < -bubbles[i].size {
                bubbles[i].position.y = screenHeight + bubbles[i].size
            } else if bubbles[i].position.y > screenHeight + bubbles[i].size {
                bubbles[i].position.y = -bubbles[i].size
            }

            // Gentle z-depth oscillation
            bubbles[i].zDepth = Float(0.5 + 0.3 * sin(currentTime * 0.5 + Double(i)))
        }
    }

    private func randomEdgePosition() -> CGPoint {
        let edge = Int.random(in: 0...3)
        switch edge {
        case 0: return CGPoint(x: CGFloat.random(in: 0...screenWidth), y: -50)
        case 1: return CGPoint(x: screenWidth + 50, y: CGFloat.random(in: 0...screenHeight))
        case 2: return CGPoint(x: CGFloat.random(in: 0...screenWidth), y: screenHeight + 50)
        default: return CGPoint(x: -50, y: CGFloat.random(in: 0...screenHeight))
        }
    }
}

struct LockBubble: Identifiable {
    let id: UUID
    var position: CGPoint
    var size: CGFloat
    var velocity: CGPoint
    var zDepth: Float
    var hasLaunched: Bool
    var launchTime: Double
}

// MARK: - Privacy Blur View

struct PrivacyBlurView: View {
    var body: some View {
        ZStack {
            AppColors.signalMercuryDark
                .ignoresSafeArea()

            // Glass overlay
            LockScreenGlassOverlay()
                .opacity(0.4)

            VStack(spacing: 16) {
                Image("AxonLight")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .opacity(0.6)

                Text("Axon")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AppLockView(isUnlocked: .constant(false))
}
