//
//  AccountabilityGoals.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/20/25.
//

import Foundation

// A simple structure to hold the user's accountability goals.
// Codable conformance allows us to easily encode/decode it for storage.
struct AccountabilityGoals: Codable {
    var productiveKeywords: [String]
    var distractingKeywords: [String]
    
    // An example of a more complex goal you could add later
    // var allowedApps: [String]
}
