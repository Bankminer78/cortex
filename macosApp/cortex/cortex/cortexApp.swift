//
//  cortexApp.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/20/25.
//

import SwiftUI
import SwiftData

@main
struct cortexApp: App {
//    var sharedModelContainer: ModelContainer = {
//        let schema = Schema([
//            Item.self,
//        ])
//        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
//
//        do {
//            return try ModelContainer(for: schema, configurations: [modelConfiguration])
//        } catch {
//            fatalError("Could not create ModelContainer: \(error)")
//        }
//    }()
//
//    var body: some Scene {
//        WindowGroup {
//            ContentView()
//        }
//        .modelContainer(sharedModelContainer)
//    }
    // Create a single instance of GoalManager and BackgroundService
    // @StateObject ensures it's managed by SwiftUI
    @StateObject private var goalManager = GoalManager()
    private let backgroundService = BackgroundService()
    
    var body: some Scene {
        WindowGroup {
            // Conditionally show OnboardingView or a "Running" view
            if !goalManager.hasCompletedOnboarding {
                OnboardingView()
                    .environmentObject(goalManager) // Pass the manager to the view
            } else {
                // Onboarding is done. You can show a simple status view.
                VStack {
                    Text("✅ Accountability App is Running")
                        .font(.headline)
                    Text("The app is monitoring in the background. You can close this window.")
                        .foregroundColor(.secondary)
                }
                .frame(width: 400, height: 200)
                .onAppear(perform: startBackgroundService) // Start service when this view appears
            }
        }
    }
    
    private func startBackgroundService() {
        // Retrieve the rules the user just set up
        guard let goals = goalManager.loadGoals() else {
            print("Could not load goals to start background service.")
            return
        }
        
        // Pass the rules to the background service
        // (We will need to add this method to BackgroundService next)
        backgroundService.configure(with: goals.verifiableRules)
        backgroundService.start()
    }
}
