import Foundation
import AppKit
import CoreGraphics
import Vision // Still useful for handling image types

class BackgroundService {
    
    private var timer: Timer?
    
    // This will hold the user's raw goal, e.g., "stop watching youtube".
    private var userGoal: String = ""

    // This method is now simpler. It just takes the raw goal string.
    func configure(with goal: String) {
        self.userGoal = goal
        print("Background service configured with goal: \(self.userGoal)")
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performTasks()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func performTasks() {
        guard !userGoal.isEmpty else {
            print("No goal set. Skipping task.")
            return
        }
        
        guard let screenshot = captureScreen() else {
            print("Failed to capture screen.")
            return
        }
        
        // Perform inference using the multimodal LLM
        performMultimodalInference(on: screenshot)
    }

    private func captureScreen() -> CGImage? {
        return CGWindowListCreateImage(CGRect.infinite, .optionOnScreenOnly, kCGNullWindowID, .default)
    }
    
    // --- Multimodal Inference ---
    // This function prepares the prompt and calls a placeholder for your LLM.
    private func performMultimodalInference(on image: CGImage) {
        // 1. Create the text prompt for the LLM
        let textPrompt = "Analyze the image. Does it violate the user's goal: '\(userGoal)'? Answer only with a single word: YES or NO."
        
        // 2. Call the (placeholder) model prediction service
        // We are passing a completion handler because model inference is asynchronous
        // and can take a moment.
        predictViolation(with: image, prompt: textPrompt) { isViolation in
            if isViolation {
                self.triggerUserAction(reason: "Content violates goal: \(self.userGoal)")
            } else {
                print("✅ Screen content is compliant.")
            }
        }
    }

    /**
     * This is the placeholder for your actual Core ML model.
     * You will replace this function's contents with the code to run your specific model.
     */
    private func predictViolation(with image: CGImage, prompt: String, completion: @escaping (Bool) -> Void) {
        print("Running multimodal inference simulation...")
        
        // --- START OF MODEL PLACEHOLDER ---
        
        // To integrate your real model:
        // 1. Drag your converted .mlmodelc file into Xcode.
        // 2. Xcode generates a Swift class (e.g., `MyMultimodalModel`).
        // 3. You would initialize it: `let model = try MyMultimodalModel(configuration: config)`
        // 4. You would prepare the inputs (the image and the text prompt).
        // 5. You would call the prediction method: `let output = try model.prediction(...)`
        // 6. You would parse the output to see if it's "YES".
        
        // For now, we'll just simulate a network delay and return a random result.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            let simulatedResult = Bool.random() // Replace with actual model output parsing
            DispatchQueue.main.async {
                completion(simulatedResult)
            }
        }
        
        // --- END OF MODEL PLACEHOLDER ---
    }
    
    private func triggerUserAction(reason: String) {
        DispatchQueue.main.async {
            print("🚨 TRIGGERING USER ACTION: \(reason)")
            // Next step: Replace this with a real NSAlert or custom popup.
        }
    }
}