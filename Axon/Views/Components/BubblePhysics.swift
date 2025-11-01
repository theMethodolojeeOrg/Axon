//
//  BubblePhysics.swift
//  Axon
//
//  Created by Cline on 10/31/2025.
//

import SwiftUI
import Combine

/// Represents a single animated bubble with physics properties
struct Bubble: Identifiable {
    let id = UUID()
    var baseSize: CGFloat  // Base size of bubble
    var size: CGFloat      // Current size (changes with Z-depth)
    var position: CGPoint
    var zDepth: CGFloat    // 0.0 (far) to 1.0 (near/at surface)
    var velocity: CGVector
    var isStuck: Bool = false
    var stuckTo: UUID? = nil
    let launchDelay: Double
    var hasLaunched: Bool = false
    
    init(baseSize: CGFloat, position: CGPoint, zDepth: CGFloat, launchDelay: Double) {
        self.baseSize = baseSize
        self.size = baseSize * (0.3 + zDepth * 0.7)  // Scale with depth
        self.position = position
        self.zDepth = zDepth
        self.velocity = CGVector(
            dx: Double.random(in: -0.2...0.2),
            dy: Double.random(in: -0.2...0.2)
        )
        self.launchDelay = launchDelay
    }
}

/// Manages bubble physics simulation
class BubblePhysicsEngine: ObservableObject {
    @Published var bubbles: [Bubble] = []
    
    private let screenWidth: CGFloat
    private let screenHeight: CGFloat
    private let stickDistance: CGFloat = 40
    private let wallStickDistance: CGFloat = 20
    
    init(screenWidth: CGFloat, screenHeight: CGFloat) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        createBubbles()
    }
    
    /// Generate Gaussian-distributed random number using Box-Muller transform
    private func gaussianRandom(mean: CGFloat, stdDev: CGFloat) -> CGFloat {
        let u1 = CGFloat.random(in: 0.0001...1.0)
        let u2 = CGFloat.random(in: 0.0001...1.0)
        let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        return mean + z0 * stdDev
    }
    
    private func createBubbles() {
        // Create 14 bubbles with Gaussian distribution
        let centerX = screenWidth / 2
        let centerY = screenHeight / 2
        let stdDevX = screenWidth * 0.25  // Spread across 50% of width
        let stdDevY = screenHeight * 0.25 // Spread across 50% of height
        
        let baseSizes: [CGFloat] = [32, 24, 19, 17, 15, 15, 15, 12, 10, 10, 10, 8, 6, 6]
        
        bubbles = baseSizes.enumerated().map { index, baseSize in
            // Gaussian distribution for X and Y positions
            let x = max(baseSize, min(screenWidth - baseSize, 
                                     gaussianRandom(mean: centerX, stdDev: stdDevX)))
            let y = max(baseSize, min(screenHeight - baseSize,
                                     gaussianRandom(mean: centerY, stdDev: stdDevY)))
            
            // Random Z-depth (0.0 = far, 1.0 = near)
            let zDepth = CGFloat.random(in: 0.0...0.3)  // Start far back
            
            // Stagger launch times
            let delay = Double(index) * 0.3
            
            return Bubble(
                baseSize: baseSize,
                position: CGPoint(x: x, y: y),
                zDepth: zDepth,
                launchDelay: delay
            )
        }
    }
    
    func update(deltaTime: Double, currentTime: Double) {
        for i in 0..<bubbles.count {
            // Check if bubble should launch
            if !bubbles[i].hasLaunched && currentTime >= bubbles[i].launchDelay {
                bubbles[i].hasLaunched = true
            }
            
            guard bubbles[i].hasLaunched else { continue }
            
            // Skip stuck bubbles
            if bubbles[i].isStuck { continue }
            
            // Move bubble toward viewer (increase Z-depth)
            bubbles[i].zDepth += CGFloat(deltaTime * 0.08)  // Slow approach
            bubbles[i].zDepth = min(1.0, bubbles[i].zDepth)  // Cap at surface
            
            // Update size and opacity based on Z-depth
            bubbles[i].size = bubbles[i].baseSize * (0.3 + bubbles[i].zDepth * 0.7)
            
            // Apply gentle drift velocity
            bubbles[i].position.x += bubbles[i].velocity.dx
            bubbles[i].position.y += bubbles[i].velocity.dy
            
            // Add slight random drift
            bubbles[i].velocity.dx += Double.random(in: -0.05...0.05)
            bubbles[i].velocity.dy += Double.random(in: -0.05...0.05)
            bubbles[i].velocity.dx = max(-0.5, min(0.5, bubbles[i].velocity.dx))
            bubbles[i].velocity.dy = max(-0.5, min(0.5, bubbles[i].velocity.dy))
            
            // Check wall collisions
            checkWallCollisions(index: i)
            
            // Check bubble collisions
            checkBubbleCollisions(index: i)
        }
    }
    
    private func checkWallCollisions(index: Int) {
        let bubble = bubbles[index]
        let radius = bubble.size / 2
        
        // Top wall
        if bubble.position.y - radius <= wallStickDistance {
            bubbles[index].isStuck = true
            bubbles[index].position.y = radius + 5
            bubbles[index].velocity = .zero
        }
        
        // Left wall
        if bubble.position.x - radius <= wallStickDistance {
            bubbles[index].isStuck = true
            bubbles[index].position.x = radius + 5
            bubbles[index].velocity = .zero
        }
        
        // Right wall
        if bubble.position.x + radius >= screenWidth - wallStickDistance {
            bubbles[index].isStuck = true
            bubbles[index].position.x = screenWidth - radius - 5
            bubbles[index].velocity = .zero
        }
    }
    
    private func checkBubbleCollisions(index: Int) {
        let bubble = bubbles[index]
        
        for j in 0..<bubbles.count {
            guard index != j else { continue }
            guard bubbles[j].hasLaunched else { continue }
            
            let other = bubbles[j]
            let distance = sqrt(
                pow(bubble.position.x - other.position.x, 2) +
                pow(bubble.position.y - other.position.y, 2)
            )
            
            let minDistance = (bubble.size + other.size) / 2
            
            if distance < minDistance + stickDistance {
                // Stick bubbles together
                bubbles[index].isStuck = true
                bubbles[index].stuckTo = other.id
                bubbles[index].velocity = .zero
                
                // Position bubble next to the other
                let angle = atan2(
                    bubble.position.y - other.position.y,
                    bubble.position.x - other.position.x
                )
                bubbles[index].position = CGPoint(
                    x: other.position.x + cos(angle) * minDistance,
                    y: other.position.y + sin(angle) * minDistance
                )
                break
            }
        }
    }
}
