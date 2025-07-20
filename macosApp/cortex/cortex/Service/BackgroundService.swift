//
//  BackgroundService.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/20/25.
//

import Foundation
import AppKit // Needed for NSImage and screen capture
import CoreGraphics // Needed for CGWindowListCreateImage

class BackgroundService {
    
    private var timer: Timer?

    // Call this method when your app starts
    func start() {
        // Ensure we don't start multiple timers
        stop()
        
        // Schedule a timer to fire every 5 seconds
        // Using .main run loop to ensure UI updates (like pop-ups) are safe
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            print("Timer fired at \(Date())")
            self?.performTasks()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func performTasks() {
        // 1. Capture the screen
        guard let screenshot = captureScreen() else {
            print("Failed to capture screen.")
            return
        }
        
        // 2. Perform vision inference (Placeholder for now)
        performInference(on: screenshot)
    }

    private func captureScreen() -> CGImage? {
        // Get information about all on-screen windows
        // kCGWindowListOptionOnScreenOnly excludes off-screen windows
        // kCGNullWindowID specifies that we want all windows on the screen
        // kCGWindowImageDefault is the default option for capturing
        let image = CGWindowListCreateImage(CGRect.infinite, .optionOnScreenOnly, kCGNullWindowID, [])
        return image
    }
    
    // --- Placeholder Functions ---
    // We will implement these in later steps

    private func performInference(on image: CGImage) {
        // TODO: Integrate Core ML model to analyze the image.
        // For now, we'll just print the image size.
        print("Performing inference on image of size: \(image.width)x\(image.height)")
        
        // Example of what will happen after inference:
        let isProductive = Bool.random() // Simulate a random inference result
        
        if !isProductive {
            // 3. Trigger a user action if needed
            triggerUserAction(reason: "Detected distracting content.")
        }
    }

    private func triggerUserAction(reason: String) {
        // TODO: Display a pop-up or notification to the user.
        // We need to make sure this is called on the main thread for UI updates.
        DispatchQueue.main.async {
            print("Triggering user action: \(reason)")
            // Here you would create and show an NSAlert or a custom SwiftUI view.
        }
    }
}
