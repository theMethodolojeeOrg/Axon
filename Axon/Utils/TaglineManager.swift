//
//  TaglineManager.swift
//  Axon
//
//  Manages rotating taglines for the app
//

import Foundation
import Combine

class TaglineManager: ObservableObject {
    static let shared = TaglineManager()
    
    private let taglines = [
        "Memory-augmented AI assistant",
        "Your favorite AI models, learning from each other and you.",
        "An AI platform that aligns AI action to you.",
        "Coordinated AI systems evolving together.",
        "AI models learning together after training completes.",
        "Reality over models, learned experiences over static concepts.",
        "Knowledge is conditional. Let testing in reality lead the way.",
        "Intelligence embedded in the network."
        
    ]
    
    private let viewCountKey = "TaglineViewCount"
    private let currentTaglineIndexKey = "CurrentTaglineIndex"
    
    @Published private(set) var currentTagline: String
    
    private init() {
        // Load the current tagline index, or start with 0
        let savedIndex = UserDefaults.standard.integer(forKey: currentTaglineIndexKey)
        self.currentTagline = taglines[savedIndex]
    }
    
    /// Call this method each time a view that displays the tagline appears
    func incrementViewCount() {
        var count = UserDefaults.standard.integer(forKey: viewCountKey)
        count += 1
        
        // Every 2nd view, select a new random tagline
        if count >= 2 {
            selectNewTagline()
            count = 0
        }
        
        UserDefaults.standard.set(count, forKey: viewCountKey)
    }
    
    private func selectNewTagline() {
        let currentIndex = UserDefaults.standard.integer(forKey: currentTaglineIndexKey)
        var newIndex: Int
        
        // Select a random index that's different from the current one
        repeat {
            newIndex = Int.random(in: 0..<taglines.count)
        } while newIndex == currentIndex && taglines.count > 1
        
        UserDefaults.standard.set(newIndex, forKey: currentTaglineIndexKey)
        currentTagline = taglines[newIndex]
    }
}
