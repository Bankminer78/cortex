//
//  AnalysisService.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/19/25.
//

import Vision
import UIKit
import UserNotifications

struct AnalysisResult {
    let verdict: String // e.g., "ON-TASK" or "OFF-TASK"
    let reason: String
}

class AnalysisService {
    
    // 1. Perform OCR on the image
    func extractText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest()
        
        do {
            try requestHandler.perform([request])
            guard let observations = request.results else { return "" }
            
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            return recognizedStrings.joined(separator: "\n")
        } catch {
            print("Error performing OCR: \(error.localizedDescription)")
            return ""
        }
    }
    
    // 2. Placeholder for Local LLM analysis
    func analyze(goal: String, screenText: String) -> AnalysisResult {
        // --- THIS IS WHERE YOUR LOCAL LLM LOGIC WOULD GO ---
        // For a hackathon, you can start with simple keyword matching.
        let goalKeywords = goal.lowercased().split(separator: " ").map(String.init)
        let text = screenText.lowercased()
        
        // Example: If any goal keyword is found, assume ON-TASK.
        let isOnTask = goalKeywords.contains { keyword in
            text.contains(keyword)
        }
        
        if isOnTask {
            return AnalysisResult(verdict: "ON-TASK", reason: "Content seems related to your goal.")
        } else {
            return AnalysisResult(verdict: "OFF-TASK", reason: "This doesn't seem related to your goal. Get back to work! 💪")
        }
    }

    // 3. Trigger a local notification
    func sendNotification(result: AnalysisResult) {
        // Only notify if the user is off-task
        guard result.verdict == "OFF-TASK" else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Accountability Check"
        content.body = result.reason
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
