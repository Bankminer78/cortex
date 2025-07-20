//
//  cortexApp.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/20/25.
//

import SwiftUI

@main
struct cortexApp: App {
    // Use @StateObject to create and manage the lifecycle of the service
    @StateObject private var backgroundService: BackgroundService

    // Use @AppStorage to persist the onboarding state and the user's goal
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete: Bool = false
    @AppStorage("userGoal") private var userGoal: String = ""

    init() {
            let service: BackgroundService
            do {
                // First, attempt to create the service instance
                service = try BackgroundService()
            } catch {
                // If it fails, the app can't run, so we stop it.
                fatalError("Failed to initialize BackgroundService: \(error.localizedDescription)")
            }
            // Then, assign the successfully created instance to the StateObject
            _backgroundService = StateObject(wrappedValue: service)
        }
    
    var body: some Scene {
        WindowGroup {
            // Conditionally show OnboardingView or a "Running" view
            if !isOnboardingComplete {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
                    .environmentObject(backgroundService) // Pass the service to the view
            } else {
                // Onboarding is done. Show the main rules management interface.
                ContentView()
                    .environmentObject(backgroundService)
                    .frame(minWidth: 800, minHeight: 600)
                    .onAppear {
                        // Clear all existing rules and goals on app restart
                        print("🔄 App restart: Clearing all existing rules and resetting system")
                        backgroundService.clearAllRulesOnStartup()
                        userGoal = "" // Clear saved goal
                        
                        // Always start the service
                        backgroundService.start()
                    }
            }
        }
        .defaultSize(width: 900, height: 700)
    }
}

// A new, simple view for the running state
struct RunningView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("✅ Cortex is Running")
                .font(.headline)
            Text("The app is monitoring your activity in the background. You can close this window.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 400, height: 200)
    }
}
