import Foundation

class GoalManager: ObservableObject {
    
    @Published var currentGoals: UserGoals?
    private let userDefaultsKey = "userAccountabilityGoals"

    init() {
        self.currentGoals = loadGoals()
    }
    
    var hasCompletedOnboarding: Bool {
        return currentGoals != nil
    }

    /// Retrieves the saved goals from UserDefaults.
    /// This is the method your background service will call.
    func loadGoals() -> UserGoals? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let goals = try decoder.decode(UserGoals.self, from: data)
            return goals
        } catch {
            print("Error decoding goals: \(error)")
            return nil
        }
    }

    /// Processes raw text, generates rules, and saves them.
    func saveNewGoals(from rawInput: String) {
        // Step 1: Use our local "LLM" to generate rules.
        let rules = generateRules(from: rawInput)
        
        // Step 2: Create the UserGoals object.
        let newGoals = UserGoals(rawInput: rawInput, verifiableRules: rules, lastUpdated: Date())
        
        // Step 3: Encode and save to UserDefaults.
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(newGoals)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            
            // Step 4: Update the published property to trigger UI changes.
            DispatchQueue.main.async {
                self.currentGoals = newGoals
            }
            print("Successfully saved goals. Rules: \(rules)")
            
        } catch {
            print("Error encoding goals: \(error)")
        }
    }
    
    // --- Local "LLM" Simulation ---
    // This is a placeholder for a real LLM. It breaks down user input into
    // verifiable keywords. We will use these keywords in the vision inference step.
    private func generateRules(from text: String) -> [String] {
        let lowercasedText = text.lowercased()
        var rules = Set<String>() // Use a Set to avoid duplicates
        
        // Define keywords that map to distractions
        let distractionMap: [String: [String]] = [
            "youtube": ["youtube"],
            "twitter": ["twitter", "x.com"],
            "reddit": ["reddit"],
            "facebook": ["facebook"],
            "instagram": ["instagram"],
            "tiktok": ["tiktok"],
            "news": ["cnn", "bbc", "nytimes"],
            "shopping": ["amazon"]
        ]
        
        for (keyword, associatedTerms) in distractionMap {
            if lowercasedText.contains(keyword) {
                associatedTerms.forEach { rules.insert($0) }
            }
        }
        
        // Add any other specific words from the input that aren't already covered
        // This is a naive example, but shows the principle.
        let components = lowercasedText.components(separatedBy: .whitespacesAndNewlines)
        let potentialNewRules = components.filter { $0.count > 3 && !distractionMap.keys.contains($0) }
        potentialNewRules.forEach { rules.insert($0) }
        
        return Array(rules)
    }
}