//
//  ContentView.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/20/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var backgroundService: BackgroundService
    @State private var newGoal: String = ""
    @State private var rules: [CompiledRule] = []
    @State private var isAddingGoal = false
    @State private var refreshID = UUID()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Cortex Rules Manager")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Text("✅ Active")
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            // Add new goal section
            VStack(alignment: .leading, spacing: 12) {
                Text("Add New Goal")
                    .font(.headline)
                
                HStack {
                    TextField("Enter your goal (e.g., 'don't scroll on Instagram')", text: $newGoal)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: addGoal) {
                        if isAddingGoal {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Add Goal")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingGoal)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Rules list
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Current Rules")
                        .font(.headline)
                    Spacer()
                    Text("\(rules.filter { $0.isActive }.count)/\(rules.count) active")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Button(action: refreshRules) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Refresh rules")
                }
                
                if rules.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No rules yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Add your first goal above to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(rules, id: \.id) { rule in
                                RuleRowView(rule: rule, backgroundService: backgroundService) {
                                    refreshRules()
                                }
                            }
                        }
                        .id(refreshID)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.vertical)
        .onAppear {
            refreshRules()
        }
    }
    
    private func addGoal() {
        let goal = newGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        
        isAddingGoal = true
        Task {
            await backgroundService.addGoal(goal)
            await MainActor.run {
                newGoal = ""
                isAddingGoal = false
                refreshRules()
            }
        }
    }
    
    private func refreshRules() {
        rules = backgroundService.getAllRules()
        refreshID = UUID()
    }
}

struct RuleRowView: View {
    let rule: CompiledRule
    let backgroundService: BackgroundService
    let onUpdate: () -> Void
    
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name)
                        .font(.headline)
                        .foregroundColor(rule.isActive ? .primary : .secondary)
                    
                    Text(ruleDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Toggle button
                    Button(action: toggleRule) {
                        Image(systemName: rule.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(rule.isActive ? .green : .gray)
                            .font(.system(size: 20))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(rule.isActive ? "Disable rule" : "Enable rule")
                    
                    // Details button
                    Button(action: { showingDetails.toggle() }) {
                        Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Delete button
                    Button(action: deleteRule) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            if showingDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Conditions:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        ForEach(Array(rule.conditions.enumerated()), id: \.offset) { index, condition in
                            HStack {
                                Text("•")
                                Text("\(condition.field) \(condition.operator.rawValue) \(valueString(condition.value))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if let timeWindow = rule.timeWindow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Time Window:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Duration: \(timeWindow.durationSeconds)s, Lookback: \(timeWindow.lookbackSeconds)s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actions:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        ForEach(Array(rule.actions.enumerated()), id: \.offset) { index, action in
                            HStack {
                                Text("•")
                                Text(action.type.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if let detectionInstructions = rule.detectionInstructions {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Detection Instructions:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(detectionInstructions)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 8)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(rule.isActive ? Color.blue.opacity(0.05) : Color.gray.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rule.isActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var ruleDescription: String {
        let conditions = rule.conditions.map { "\($0.field): \(valueString($0.value))" }.joined(separator: ", ")
        let actionTypes = rule.actions.map { $0.type.rawValue }.joined(separator: ", ")
        return "When \(conditions) → \(actionTypes)"
    }
    
    private func valueString(_ value: RuleValue) -> String {
        switch value {
        case .string(let str):
            return str
        case .int(let int):
            return String(int)
        case .double(let double):
            return String(double)
        case .bool(let bool):
            return String(bool)
        case .array(let array):
            return "[\(array.count) items]"
        }
    }
    
    private func toggleRule() {
        do {
            try backgroundService.toggleRule(id: rule.id)
            onUpdate()
        } catch {
            print("Failed to toggle rule: \(error)")
        }
    }
    
    private func deleteRule() {
        do {
            try backgroundService.removeRule(id: rule.id)
            onUpdate()
        } catch {
            print("Failed to delete rule: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(try! BackgroundService())
}
