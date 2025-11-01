//
//  LaunchScreenView.swift
//  Axon
//
//  Created by Cline on 10/31/2025.
//

import SwiftUI

struct LaunchScreenView: View {
    @StateObject private var physicsEngine: BubblePhysicsEngine
    @State private var animationTime: Double = 0
    @State private var timer: Timer?
    
    // Animation states
    @State private var screenOpacity: Double = 0
    @State private var glassOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.8
    @State private var bubblesStarted: Bool = false
    @State private var isHoldingForViewing: Bool = false
    
    init() {
        let screenSize = UIScreen.main.bounds.size
        _physicsEngine = StateObject(wrappedValue: BubblePhysicsEngine(
            screenWidth: screenSize.width,
            screenHeight: screenSize.height
        ))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color - signalMercuryDark
                AppColors.signalMercuryDark
                    .ignoresSafeArea()
                
                // Layer 1: Bubbles and Logo (underneath the glass)
                ZStack {
                    // Animated bubbles with Z-depth
                    ForEach(physicsEngine.bubbles) { bubble in
                        if bubble.hasLaunched && bubblesStarted {
                            Image("Bubble")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: bubble.size, height: bubble.size)
                                .opacity(0.1 + Double(bubble.zDepth) * 0.25)  // Fade in as they approach
                                .position(bubble.position)
                                .scaleEffect(1.0 + sin(animationTime * 2 + Double(bubble.id.hashValue)) * 0.05)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: bubble.position)
                                .animation(.easeInOut(duration: 0.3), value: bubble.size)
                                .animation(.easeInOut(duration: 0.3), value: bubble.zDepth)
                        }
                    }
                    
                    // Main logo - centered
                    Image("AxonLight")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 246, height: 246)
                        .opacity(0.8)
                        .scaleEffect(logoScale)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                
                // Layer 2: Procedural glass overlay (microscope slide effect)
                ProceduralGlassOverlay()
                    .opacity(glassOpacity)
                    .allowsHitTesting(false)
                
                // Layer 3: Copyright text on top of everything
                VStack {
                    Spacer()
                    Text("Axon by NeurX.org ©2025")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .italic()
                        .foregroundColor(.white)
                        .padding(.bottom, 20)
                }
            }
            .opacity(screenOpacity)
            .onAppear {
                startAnimationSequence()
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }
    
    private func startAnimationSequence() {
        // Step 1: Fade from black (1.5s)
        withAnimation(.easeIn(duration: 1.5)) {
            screenOpacity = 1.0
        }
        
        // Step 2: Glass overlay appears (0.5s) - starts after step 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeIn(duration: 0.5)) {
                glassOpacity = 0.6
            }
            
            // Step 3: Logo scales in (0.8s) - starts after step 2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.8)) {
                    logoScale = 1.0
                }
                
                // Step 4: Bubbles start launching - starts after step 3
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    bubblesStarted = true
                    
                    // Start physics animation
                    timer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { _ in
                        animationTime += 1/60.0
                        physicsEngine.update(deltaTime: 1/60.0, currentTime: animationTime)
                    }
                    
                    // Step 5: Hold for viewing (10s) - starts after step 4
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                        isHoldingForViewing = true
                        // Note: Fade out will be handled by parent (AxonApp)
                    }
                }
            }
        }
    }
}

// MARK: - Procedural Glass Overlay

struct ProceduralGlassOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base glass shape with tint
                RoundedRectangle(cornerRadius: 60)
                    .fill(AppColors.signalMercuryDark.opacity(0.4))
                    .frame(
                        width: geometry.size.width * 1.25,
                        height: geometry.size.height * 1.25
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Radial gradient for -45° lighting effect
                // Bright center, dark corners at top-right and bottom-left
                RoundedRectangle(cornerRadius: 60)
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.2), location: 0.3),
                                .init(color: Color.white.opacity(0.1), location: 0.5),
                                .init(color: Color.white.opacity(0.05), location: 0.7),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            center: UnitPoint(x: 0.4, y: 0.4),
                            startRadius: 50,
                            endRadius: 600
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

#Preview {
    LaunchScreenView()
}
