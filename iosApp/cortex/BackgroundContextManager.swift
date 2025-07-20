//
//  BackgroundContextManager.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/19/25.
//

import BackgroundTasks
import UIKit // For UIImage

class BackgroundTaskManager {
    let taskIdentifier = "com.cortex.apprefresh"
    let networkService = NetworkService()
    let analysisService = AnalysisService()
    
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // Fetch no earlier than 15 minutes from now

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background task scheduled.")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule a new task for the future
        scheduleAppRefresh()
        
        // Define an expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // --- Main Background Work ---
        Task {
            // 1. Fetch screenshot
            guard let image = await networkService.fetchScreenshot() else {
                task.setTaskCompleted(success: false)
                return
            }
            
            // 2. Analyze
            let goal = UserDefaults.standard.string(forKey: "userGoal") ?? ""
            let screenText = await analysisService.extractText(from: image)
            let result = analysisService.analyze(goal: goal, screenText: screenText)
            
            // 3. Notify user if needed
            analysisService.sendNotification(result: result)
            
            // 4. Mark task as complete
            task.setTaskCompleted(success: true)
        }
    }
}
