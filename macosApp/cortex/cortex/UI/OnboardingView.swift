//
//  OnboardingView.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/20/25.
//

import SwiftUI

struct OnboardingView: View {
    // We get the GoalManager from the environment
    @EnvironmentObject var goalManager: GoalManager
    
    @State private var distractionInput: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set Your Goals")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Describe the apps, websites, or content you want to avoid. The app will work in the background to help you stay on track.")
                .foregroundColor(.secondary)

            TextEditor(text: $distractionInput)
                .font(.body)
                .frame(height: 150)
                .border(Color.gray.opacity(0.3), width: 1)
                .cornerRadius(5)
            
            Button(action: {
                // When the button is clicked, save the goals.
                // This will trigger the change in the main app view.
                goalManager.saveNewGoals(from: distractionInput)
            }) {
                Text("Save Goals and Start")
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
        OnboardingView()
            .environmentObject(GoalManager())
    }
}
