import Foundation
import AppKit
import CoreGraphics
import Vision
import ScreenCaptureKit

@available(macOS 14.0, *)
class BackgroundService: ObservableObject, @unchecked Sendable {
    
    private var timer: Timer?
    private var isProcessingLLM = false
    
    // Modular components
    private let llmClient = LLMClient()
    private let databaseManager: DatabaseManager
    private let screenCaptureManager = ScreenCaptureManager()
    private let ruleEngine = RuleEngine()
    private var actionDispatcher: ActionDispatcher!
    
    // This will hold the user's raw goal, e.g., "stop watching youtube".
    private var userGoal: String = ""
    
    init() throws {
        // Initialize database manager
        self.databaseManager = try DatabaseManager()
        
        // Initialize action dispatcher on main actor
        Task { @MainActor in
            self.actionDispatcher = ActionDispatcher()
            
            // Set up LLM message generator for ActionDispatcher
            self.actionDispatcher.setLLMMessageGenerator { [weak self] prompt, image in
                guard let self = self else { throw LLMError.missingAPIKey("Service deallocated") }
                
                // Always make an LLM call - we should now have the image context
                if let image = image {
                    print("🤖 Making LLM call with screenshot for popup message")
                    let response = try await self.llmClient.analyze(image: image, prompt: prompt)
                    return response.content
                } else {
                    // Fallback if no image is provided
                    print("⚠️ No image provided to LLM popup - using fallback message")
                    return "Take a moment to consider: does this purchase align with your values and financial goals? Retailers often use urgency and scarcity to trigger impulse buying. The 24-hour rule can help you make more mindful decisions."
                }
            }
        }
        
    }
    
    deinit {
        // Close database when service is deallocated
        databaseManager.close()
    }

    // MARK: - Setup
    
   
//    private func setupDefaultRules() {
//        // Add default Instagram scrolling rule
//        let instagramRule = CompiledRule(
//            name: "Instagram Scrolling Limit",
//            type: .timeWindow,
//            conditions: [
//                RuleCondition(field: "activity", `operator`: .equal, value: .string("scrolling")),
//                RuleCondition(field: "domain", `operator`: .equal, value: .string("instagram.com"))
//            ],
//            logicalOperator: .and,
//            timeWindow: TimeWindowConfig(durationSeconds: 10, lookbackSeconds: 15, threshold: 2),
//            actions: [
//                RuleAction(type: .popup, parameters: ["message": .string("You've been scrolling Instagram too long!")])
//            ]
//        )
//        
//        // Add buying activity intervention rule - triggers if ANY buying activity detected in past 10 seconds
//        let buyingRule = CompiledRule(
//            name: "Amazon Buying Intervention",
//            type: .timeWindow,
//            conditions: [
//                RuleCondition(field: "activity", `operator`: .equal, value: .string("buying"))
//            ],
//            timeWindow: TimeWindowConfig(durationSeconds: 1, lookbackSeconds: 10, threshold: 1), // Any buying activity in past 10 seconds
//            actions: [
//                RuleAction(type: .llmPopup, parameters: [
//                    "title": .string("💳 Mindful Spending Moment"),
//                    "prompt": .string("psychology_of_spending")
//                ])
//            ]
//        )
//        
//        // Add YouTube watching intervention rule - switches to Notion when watching YouTube
//        let youtubeRule = CompiledRule(
//            name: "YouTube Watching Intervention",
//            type: .timeWindow,
//            conditions: [
//                RuleCondition(field: "activity", `operator`: .equal, value: .string("watching")),
//                RuleCondition(field: "domain", `operator`: .equal, value: .string("youtube.com"))
//            ],
//            logicalOperator: .and,
//            timeWindow: TimeWindowConfig(durationSeconds: 1, lookbackSeconds: 5, threshold: 1), // Any watching activity in past 5 seconds
//            actions: [
//                RuleAction(type: .appSwitch, parameters: ["targetApp": .string("Notion"), "message": .string("Switching to Notion to help you stay productive")])
//            ]
//        )
//        
//        do {
//            try ruleEngine.addRule(instagramRule)
//            try ruleEngine.addRule(buyingRule)
//            try ruleEngine.addRule(youtubeRule)
//            print("✅ Default rules configured: Instagram scrolling + Amazon buying intervention + YouTube watching intervention")
//        } catch {
//            print("❌ Failed to add default rules: \(error)")
//        }
//    }
    
    private func setupRule(from goal: String) async {
        print("⚙️ Compiling rule from natural language goal: '\(goal)'")
        do {
            // 1. Call LLM to get JSON representation of the rule
            let llmResponse = try await llmClient.generateRuleJSON(from: goal)
            let ruleJSONString = llmResponse.content
            print("🤖 LLM generated rule JSON: \(ruleJSONString)")

            // 2. Decode the JSON string into a CompiledRule object
            guard let jsonData = ruleJSONString.data(using: .utf8) else {
                print("❌ Failed to convert JSON string to Data")
                return
            }
            
            print("jsondata \(jsonData)")

                let decoder = JSONDecoder()
                // Re-add this line for robust decoding of snake_case keys
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                    
                do {
                    let compiledRule = try decoder.decode(CompiledRule.self, from: jsonData)
                    print("🔹 Decoded rule: \(compiledRule)")
                    
                    if let instructions = compiledRule.detectionInstructions {
                        print("🎯 Rule includes detection instructions: \(instructions.prefix(100))...")
                    } else {
                        print("⚠️ Rule missing detection instructions")
                    }

                    // 3. Add the rule to the rule engine
                    try ruleEngine.addRule(compiledRule)
                    print("✅ Rule successfully compiled and added: \(compiledRule.name)")
                } catch {
                    // Added more detailed error logging
                    if let decodingError = error as? DecodingError {
                        print("❌ Decoding Error: \(decodingError)")
                    }
                    print("❌ Failed to setup rule from natural language: \(error.localizedDescription)")
                }

        } catch {
            print("❌ Failed to setup rule from natural language: \(error.localizedDescription)")
        }
    }
    
    func configure(with goal: String) {
        self.userGoal = goal
        print("Background service configured with goal: \(self.userGoal)")

        // Asynchronously set up the rule from the user's goal
        Task {
            await setupRule(from: goal)
        }
    }
    
    // MARK: - Rule Management for UI
    
    func getAllRules() -> [CompiledRule] {
        return ruleEngine.getAllRules()
    }
    
    func toggleRule(id: String) throws {
        try ruleEngine.toggleRule(id: id)
    }
    
    func removeRule(id: String) throws {
        try ruleEngine.removeRule(id: id)
    }
    
    func addGoal(_ goal: String) async {
        await setupRule(from: goal)
        
        // Start monitoring if this is the first active rule and service isn't already processing
        let activeRules = getAllRules().filter { $0.isActive }
        if !activeRules.isEmpty && !isProcessingLLM {
            print("🔄 Starting monitoring loop with \\(activeRules.count) active rule(s)")
            performTasks()
        }
    }
    
    func getCombinedDetectionInstructions() -> String {
        return ruleEngine.getCombinedDetectionInstructions()
    }
    
    func clearAllRulesOnStartup() {
        ruleEngine.clearAllRules()
    }

    func start() {
        stop()
        
        // Request permissions
        Task {
            await requestScreenCapturePermission()
        }
        
        // Start the first cycle manually - subsequent cycles are triggered after LLM completion
        performTasks()
    }
    
    private func requestScreenCapturePermission() async {
        do {
            try await screenCaptureManager.requestPermissions()
            print("✅ Screen capture permissions granted")
        } catch {
            print("⚠️ Screen capture permission error: \(error)")
            print("Please grant Screen Recording permission in System Preferences > Privacy & Security")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        // Don't close database here - it should stay open for the lifetime of the service
        // databaseManager.close()
        print("🛑 Background service stopped")
    }

    private func performTasks() {
        // Check if we have any active rules
        let activeRules = getAllRules().filter { $0.isActive }
        guard !activeRules.isEmpty else {
            print("No active rules. Skipping monitoring cycle.")
            return
        }
        
        // Prevent cascading LLM calls
        guard !isProcessingLLM else {
            print("🔄 LLM processing in progress, skipping cycle")
            return
        }
        
        Task {
            await checkAndProcessFocusedWindow()
        }
    }
    
    // MARK: - Main Processing
    
    private func checkAndProcessFocusedWindow() async {
        isProcessingLLM = true
        
        // Get foreground app info
        guard let foregroundApp = screenCaptureManager.getForegroundApp() else {
            print("🔍 No foreground app detected")
            scheduleNextCycle()
            return
        }
        
        print("🎯 Foreground app: \(foregroundApp.bundleIdentifier ?? "unknown") - \(foregroundApp.localizedName ?? "unknown")")
        
        // Only process Safari and Messages
        guard foregroundApp.bundleIdentifier == "com.apple.Safari" || 
              foregroundApp.bundleIdentifier == "com.apple.MobileSMS" else {
            print("🚫 Skipping LLM analysis - only Safari and Messages are monitored currently")
            scheduleNextCycle()
            return
        }
        
        // Capture screenshot for Safari or Messages
        do {
            let captureResult: CaptureResult?
            
            if foregroundApp.bundleIdentifier == "com.apple.Safari" {
                captureResult = try await screenCaptureManager.captureSafariWindow()
                guard let result = captureResult else {
                    print("⚠️ Failed to capture Safari window")
                    scheduleNextCycle()
                    return
                }
                print("📸 Safari window captured: \(result.image.width)x\(result.image.height)")
            } else {
                // Messages app
                captureResult = try await screenCaptureManager.captureMessagesWindow()
                guard let result = captureResult else {
                    print("⚠️ Failed to capture Messages window")
                    scheduleNextCycle()
                    return
                }
                print("📸 Messages window captured: \(result.image.width)x\(result.image.height)")
            }
            
            // Save debug image
            try saveDebugImage(captureResult!.image)
            
            // Process with LLM
            await processWithLLM(captureResult: captureResult!, appInfo: foregroundApp)
            
        } catch {
            print("❌ Screen capture failed for \(foregroundApp.localizedName ?? "unknown"): \(error)")
            scheduleNextCycle()
        }
    }
    
    private func scheduleNextCycle() {
        isProcessingLLM = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.performTasks()
        }
    }
    
    // MARK: - LLM Processing
    
    private func processWithLLM(captureResult: CaptureResult, appInfo: AppInfo) async {
        do {
            // Create activity classification prompt
            let prompt = createActivityPrompt(for: appInfo)
            
            // Analyze with LLM
            let llmResponse = try await llmClient.analyze(image: captureResult.image, prompt: prompt)
            let activity = llmResponse.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
            
            print("🤖 LLM Response: '\(activity)' from \(llmResponse.provider)")
            
            // Determine productivity
            let productive = isActivityProductive(activity)
            
            // Extract domain using new AppleScript method for Safari
            let domain = await extractDomainFromSafari(appInfo: appInfo)
            
            // Create activity record
            let activityRecord = ActivityRecord(
                activity: activity,
                productive: productive,
                app: appInfo.localizedName ?? "Unknown",
                bundleId: appInfo.bundleIdentifier,
                domain: domain
            )
            
            // Debug logging
            print("🔍 Debug - Activity: '\(activity)', Domain: '\(domain ?? "nil")', App: '\(appInfo.localizedName ?? "Unknown")', BundleID: '\(appInfo.bundleIdentifier ?? "unknown")'")
            
            // Log to database
            let recordId = try databaseManager.logActivity(activityRecord)
            print("📊 Activity logged: ID=\(recordId)")
            
            // Evaluate rules
            let violations = try await ruleEngine.evaluateRules(for: activityRecord, with: databaseManager)
            print("🔍 Debug - Found \(violations.count) rule violations")
            
            // Debug rule matching
            let activeRules = getAllRules().filter { $0.isActive }
            for rule in activeRules {
                let matches = rule.conditions.allSatisfy { condition in
                    let fieldValue: String
                    switch condition.field {
                    case "activity": fieldValue = activityRecord.activity
                    case "app": fieldValue = activityRecord.app
                    case "domain": fieldValue = activityRecord.domain ?? ""
                    default: fieldValue = ""
                    }
                    let conditionValue = condition.value
                    if case .string(let value) = conditionValue {
                        return fieldValue == value
                    }
                    return false
                }
                print("🔍 Rule '\(rule.name)' matches: \(matches) (looking for activity='\(rule.conditions.first { $0.field == "activity" }?.value)', got '\(activityRecord.activity)')")
            }
            
            // Dispatch actions for violations
            await handleRuleViolations(violations, captureResult: captureResult)
            
        } catch {
            print("❌ LLM processing failed: \(error)")
        }
        
        // Schedule next cycle
        scheduleNextCycle()
    }
    
    private func createActivityPrompt(for appInfo: AppInfo) -> String {
        // Get dynamic detection instructions from active rules
        let dynamicInstructions = getCombinedDetectionInstructions()
        
        if appInfo.bundleIdentifier == "com.apple.Safari" {
            // Base prompt for Safari
            var prompt = """
            Look at this screenshot and identify what the user is doing.
            
            """
            
            // Add dynamic instructions from rules if available
            if !dynamicInstructions.isEmpty {
                print("🎯 Using dynamic detection instructions from \(ruleEngine.getRules().count) active rules")
                prompt += dynamicInstructions + "\n\n"
            } else {
                print("⚠️ No active rules with detection instructions, using fallback detection")
                // Fallback to basic hardcoded instructions if no rules are active
                prompt += """
                Basic activity detection:
                - "browsing" for general web browsing
                - "watching" for video content
                - "social" for social media activities
                - "shopping" for e-commerce activities
                - "other" for anything else
                
                """
            }
            
            prompt += """
            Respond with ONLY ONE WORD describing the primary activity you observe.
            """
            
            return prompt
            
        } else if appInfo.bundleIdentifier == "com.apple.MobileSMS" {
            // Messages app with dynamic detection instructions
            var prompt = """
            Look at this Messages screenshot carefully.
            
            """
            
            // Add dynamic instructions from rules if available
            if !dynamicInstructions.isEmpty {
                print("🎯 Using dynamic detection instructions for Messages from \(ruleEngine.getRules().count) active rules")
                prompt += dynamicInstructions + "\n\n"
            } else {
                print("⚠️ No active rules with detection instructions for Messages, using fallback detection")
                // Fallback to basic hardcoded instructions if no rules are active
                prompt += """
                Basic messaging activity detection:
                - "messaging" for general messaging activities
                - "texting" for active text conversations
                - "other" for anything else
                
                """
            }
            
            prompt += """
            Respond with ONLY ONE WORD describing the primary messaging activity you observe.
            """
            
            return prompt
        } else {
            // Generic app handling
            return """
            Look at this screenshot of the \(appInfo.localizedName ?? "application") app and identify what the user is doing.
            
            Respond with ONE WORD describing the activity:
            - "productive" for work-related activities
            - "browsing" for general browsing or exploration
            - "entertainment" for videos/movies/games
            - "social" for social media activities  
            - "other" for anything else
            """
        }
    }
    
    private func isActivityProductive(_ activity: String) -> Bool {
        let unproductiveActivities = ["scrolling", "gaming", "entertainment", "social"]
        return !unproductiveActivities.contains(activity)
    }
    
    private func extractDomainFromSafari(appInfo: AppInfo) async -> String? {
        guard appInfo.bundleIdentifier == "com.apple.Safari" else { return nil }
        
        // Use AppleScript to get the actual Safari URL
        if let safariURL = await screenCaptureManager.getSafariCurrentURL() {
            return screenCaptureManager.extractDomainFromURL(safariURL)
        }
        
        // Fallback to legacy method if AppleScript fails
        print("⚠️ AppleScript failed, falling back to window title parsing")
        return screenCaptureManager.extractDomain(from: nil)
    }
    
    @available(*, deprecated, message: "Use extractDomainFromSafari instead")
    private func extractDomain(from windowTitle: String?, appInfo: AppInfo) -> String? {
        guard appInfo.bundleIdentifier == "com.apple.Safari" else { return nil }
        return screenCaptureManager.extractDomain(from: windowTitle)
    }
    
    private func handleRuleViolations(_ violations: [RuleViolation], captureResult: CaptureResult) async {
        guard let actionDispatcher = actionDispatcher else {
            print("⚠️ ActionDispatcher not initialized yet")
            return
        }
        
        for violation in violations {
            print("🚨 Processing violation: \(violation.rule.name)")
            
            for action in violation.rule.actions {
                let dispatchableAction = convertToDispatchableAction(action, violation: violation, captureResult: captureResult)
                let result = await actionDispatcher.dispatch(dispatchableAction)
                
                if result.success {
                    print("✅ Action executed: \(action.type)")
                } else {
                    print("❌ Action failed: \(action.type) - \(result.error?.localizedDescription ?? "unknown error")")
                }
            }
        }
    }
    
    private func convertToDispatchableAction(_ ruleAction: RuleAction, violation: RuleViolation, captureResult: CaptureResult) -> DispatchableAction {
        switch ruleAction.type {
        case .popup:
            let message = extractStringParameter(ruleAction.parameters["message"]) ?? 
                         "Rule violation detected: \(violation.rule.name)"
            let config = PopupConfig(
                title: "Productivity Alert",
                message: message,
                style: .warning
            )
            return .popup(config)
            
        case .llmPopup:
            let title = extractStringParameter(ruleAction.parameters["title"]) ?? "Mindful Moment"
            let promptKey = extractStringParameter(ruleAction.parameters["prompt"]) ?? "generic"
            
            // Generate psychology of spending prompt for buying activity
            let prompt = createSpendingPsychologyPrompt()
            
            let config = LLMPopupConfig(
                title: title,
                prompt: prompt,
                style: .warning,
                contextImage: captureResult.image  // Pass the screenshot to LLM for analysis
            )
            return .llmPopup(config)
            
        case .notification:
            let message = extractStringParameter(ruleAction.parameters["message"]) ?? 
                         "Rule violation: \(violation.rule.name)"
            let config = NotificationConfig(
                title: "Cortex Alert",
                body: message
            )
            return .notification(config)
            
        case .block:
            let duration = extractDoubleParameter(ruleAction.parameters["duration"]) ?? 300.0
            let config = BlockConfig(
                bundleIdentifiers: [violation.triggerActivity.bundleId ?? ""],
                duration: duration
            )
            return .block(config)
            
        case .log:
            let message = "Rule violation: \(violation.rule.name) - \(violation.triggerActivity.activity)"
            let config = LogConfig(level: .warning, message: message)
            return .log(config)
            
        case .browserBack:
            let message = extractStringParameter(ruleAction.parameters["message"])
            let showPopup = extractBoolParameter(ruleAction.parameters["showPopup"]) ?? false
            let config = BrowserBackConfig(
                popupMessage: message,
                showPopup: showPopup
            )
            return .browserBack(config)
            
        case .appSwitch:
            let targetApp = extractStringParameter(ruleAction.parameters["targetApp"]) ?? "Notion"
            let message = extractStringParameter(ruleAction.parameters["message"])
            let config = AppSwitchConfig(
                targetApp: targetApp,
                bundleId: "notion.id", // Default to Notion bundle ID
                switchMessage: message
            )
            return .appSwitch(config)
            
        case .motivationalLockScreen:
            let title = extractStringParameter(ruleAction.parameters["title"]) ?? "✨ Focus Time"
            let prompt = extractStringParameter(ruleAction.parameters["prompt"]) ?? "motivational_focus"
            let duration = extractDoubleParameter(ruleAction.parameters["duration"]) ?? 300.0
            let backgroundColor = extractStringParameter(ruleAction.parameters["backgroundColor"]) ?? "#FFB6C1"
            let emojiIcon = extractStringParameter(ruleAction.parameters["emojiIcon"]) ?? "😊"
            
            let config = MotivationalLockScreenConfig(
                title: title,
                prompt: prompt,
                duration: duration,
                allowOverride: true,
                blockedApps: [violation.triggerActivity.bundleId ?? ""],
                backgroundColor: backgroundColor,
                emojiIcon: emojiIcon
            )
            return .motivationalLockScreen(config)
            
        case .screenTimeShield:
            let domains = extractArrayParameter(ruleAction.parameters["domains"]) ?? ["instagram.com"]
            let duration = extractDoubleParameter(ruleAction.parameters["duration"]) ?? 300.0
            let blockMessage = extractStringParameter(ruleAction.parameters["blockMessage"])
            let allowOverride = extractBoolParameter(ruleAction.parameters["allowOverride"]) ?? false
            
            let config = ScreenTimeShieldConfig(
                domains: domains,
                duration: duration,
                blockMessage: blockMessage,
                allowOverride: allowOverride
            )
            return .screenTimeShield(config)
            
        case .closeBrowserTab:
            let message = extractStringParameter(ruleAction.parameters["message"])
            let showNotification = extractBoolParameter(ruleAction.parameters["showNotification"]) ?? true
            
            let config = CloseBrowserTabConfig(
                message: message,
                showNotification: showNotification
            )
            return .closeBrowserTab(config)
            
        case .webhook:
            // Default webhook configuration
            let url = URL(string: "http://localhost:3000/webhook")!
            let body: [String: Any] = [
                "rule": violation.rule.name,
                "activity": violation.triggerActivity.activity,
                "timestamp": violation.timestamp.timeIntervalSince1970
            ]
            let config = WebhookConfig(url: url, body: body)
            return .webhook(config)
        }
    }
    
    // MARK: - Utility Methods
    
    private func saveDebugImage(_ image: CGImage) throws {
        let _ = try screenCaptureManager.saveImage(image, withPrefix: "cortex_debug")
    }
    
    private func createSpendingPsychologyPrompt() -> String {
        return """
        You can see the user is about to make a purchase online. Create a funny and engaging message to help them think twice about their purchase.
        """
    }
    
    private func extractStringParameter(_ value: RuleValue?) -> String? {
        guard case .string(let stringValue) = value else { return nil }
        return stringValue
    }
    
    private func extractDoubleParameter(_ value: RuleValue?) -> Double? {
        switch value {
        case .double(let doubleValue):
            return doubleValue
        case .int(let intValue):
            return Double(intValue)
        default:
            return nil
        }
    }
    
    private func extractBoolParameter(_ value: RuleValue?) -> Bool? {
        guard case .bool(let boolValue) = value else { return nil }
        return boolValue
    }
    
    private func extractArrayParameter(_ value: RuleValue?) -> [String]? {
        guard case .array(let arrayValue) = value else { return nil }
        return arrayValue.compactMap { item in
            if case .string(let stringValue) = item {
                return stringValue
            }
            return nil
        }
    }
}
