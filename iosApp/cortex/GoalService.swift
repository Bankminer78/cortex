//
//  GoalService.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/19/25.
//

import Foundation

class GoalService: ObservableObject {
    @Published var userGoal: String {
        didSet {
            UserDefaults.standard.set(userGoal, forKey: "userGoal")
        }
    }
    
    init() {
        self.userGoal = UserDefaults.standard.string(forKey: "userGoal") ?? "example: no more doom scrolling on instagram"
    }
}
