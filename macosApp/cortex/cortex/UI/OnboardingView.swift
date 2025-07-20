//
//  OnboardingView.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/20/25.
//

import SwiftUI

struct OnboardingView: View {
    
    @EnvironmentObject var backgroundService: BackgroundService
    @Binding var isOnboardingComplete: Bool
    
    // Use AppStorage to save the goal persistently
    @AppStorage("userGoal") private var userGoal: String = ""
    
    @State private var distractionInput: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set Your Goal")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Describe what you want to avoid in a single sentence. For example, 'don't scroll on instagram but messaging is fine' or 'stop me from buying things on amazon'.")
                .foregroundColor(.secondary)

            TextEditor(text: $distractionInput)
                .font(.body)
                .frame(height: 100)
                .border(Color.gray.opacity(0.3), width: 1)
                .cornerRadius(5)
            
            Button(action: {
                // 1. Save the goal to persistent storage
                self.userGoal = self.distractionInput
                
                // 2. Configure and start the background service
                backgroundService.configure(with: self.userGoal)
                backgroundService.start()
                
                // 3. Mark onboarding as complete to switch views
                self.isOnboardingComplete = true
            }) {
                Text("Save Goal and Start")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(distractionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(30)
        .frame(width: 450)
    }
}

// For previewing the view
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a dummy service for the preview
        let service: BackgroundService? = {
            do {
                return try BackgroundService()
            } catch {
                return nil
            }
        }()
        
        OnboardingView(isOnboardingComplete: .constant(false))
            .environmentObject(service!)
    }
}
