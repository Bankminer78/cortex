//
//  cortexApp.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/19/25.
//
import SwiftUI
import UserNotifications

@main
struct CortexApp: App {
    // Get the scene phase to detect when the app goes to the background
    @Environment(\.scenePhase) private var scenePhase
    
    private let backgroundTaskManager = BackgroundTaskManager()

    init() {
        // Register the background task when the app initializes
        backgroundTaskManager.registerBackgroundTask()
        requestNotificationPermission()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                // Schedule the background task when the app is backgrounded
                backgroundTaskManager.scheduleAppRefresh()
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
}
