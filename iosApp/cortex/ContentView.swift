//
//  ContentView.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/19/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var goalService = GoalService()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Cortex - Your Accountability Partner")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("How do you want to change how you use your phone?")
                .font(.headline)
            
            TextEditor(text: $goalService.userGoal)
                .frame(height: 150)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray, lineWidth: 1)
                )
            
            Text("Your goal will be saved automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
}
