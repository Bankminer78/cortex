import Foundation
import AppKit
import CoreGraphics
import Vision
import ScreenCaptureKit

@available(macOS 14.0, *)
class BackgroundService: @unchecked Sendable {
    
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
        
        // Add default rule
        setupDefaultRules()
    }
    
    deinit {
        // Close database when service is deallocated
        databaseManager.close()
    }

    // MARK: - Setup
    
    private func setupDefaultRules() {
        // Add default Instagram scrolling rule
        let instagramRule = CompiledRule(
            name: "Instagram Scrolling Limit",
            type: .timeWindow,
            conditions: [
                RuleCondition(field: "activity", `operator`: .equal, value: .string("scrolling")),
                RuleCondition(field: "domain", `operator`: .equal, value: .string("instagram.com"))
            ],
            logicalOperator: .and,
            timeWindow: TimeWindowConfig(durationSeconds: 10, lookbackSeconds: 15, threshold: 2),
            actions: [
                RuleAction(type: .popup, parameters: ["message": .string("You've been scrolling Instagram too long!")])
            ]
        )
        
        // Add buying activity intervention rule - triggers if ANY buying activity detected in past 10 seconds
        let buyingRule = CompiledRule(
            name: "Amazon Buying Intervention",
            type: .timeWindow,
            conditions: [
                RuleCondition(field: "activity", `operator`: .equal, value: .string("buying"))
            ],
            timeWindow: TimeWindowConfig(durationSeconds: 1, lookbackSeconds: 10, threshold: 1), // Any buying activity in past 10 seconds
            actions: [
                RuleAction(type: .llmPopup, parameters: [
                    "title": .string("💳 Mindful Spending Moment"),
                    "prompt": .string("psychology_of_spending")
                ])
            ]
        )
        
        // Add YouTube watching intervention rule - switches to Notion when watching YouTube
        let youtubeRule = CompiledRule(
            name: "YouTube Watching Intervention",
            type: .timeWindow,
            conditions: [
                RuleCondition(field: "activity", `operator`: .equal, value: .string("watching")),
                RuleCondition(field: "domain", `operator`: .equal, value: .string("youtube.com"))
            ],
            logicalOperator: .and,
            timeWindow: TimeWindowConfig(durationSeconds: 1, lookbackSeconds: 5, threshold: 1), // Any watching activity in past 5 seconds
            actions: [
                RuleAction(type: .appSwitch, parameters: ["targetApp": .string("Notion"), "message": .string("Switching to Notion to help you stay productive")])
            ]
        )
        
        do {
            try ruleEngine.addRule(instagramRule)
            try ruleEngine.addRule(buyingRule)
            try ruleEngine.addRule(youtubeRule)
            print("✅ Default rules configured: Instagram scrolling + Amazon buying intervention + YouTube watching intervention")
        } catch {
            print("❌ Failed to add default rules: \(error)")
        }
    }
    
    // This method is now simpler. It just takes the raw goal string.
    func configure(with goal: String) {
        self.userGoal = goal
        print("Background service configured with goal: \(self.userGoal)")
    }

    func start() {
        stop()
        
        // Request permissions
        Task {
            await requestScreenCapturePermission()
        }
        
        // COMMENTED OUT: Timer-based loop
        // timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
        //     self?.performTasks()
        // }
        
        // Start the first cycle manually
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
        guard !userGoal.isEmpty else {
            print("No goal set. Skipping task.")
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
            print("🔍 Debug - Activity: '\(activity)', Domain: '\(domain ?? "nil")', App: \(appInfo.localizedName ?? "Unknown")")
            
            // Log to database
            let recordId = try databaseManager.logActivity(activityRecord)
            print("📊 Activity logged: ID=\(recordId)")
            
            // Evaluate rules
            let violations = try await ruleEngine.evaluateRules(for: activityRecord, with: databaseManager)
            print("🔍 Debug - Found \(violations.count) rule violations")
            
            // Dispatch actions for violations
            await handleRuleViolations(violations, captureResult: captureResult)
            
        } catch {
            print("❌ LLM processing failed: \(error)")
        }
        
        // Schedule next cycle
        scheduleNextCycle()
    }
    
    private func createActivityPrompt(for appInfo: AppInfo) -> String {
        if appInfo.bundleIdentifier == "com.apple.Safari" {
            return """
            Look at this screenshot and identify what the user is doing. 
            
            If this is Instagram, determine the specific activity:
            - "messaging" if they are in Instagram DMs/messages talking to friends
            - "scrolling" if they are browsing the feed, stories, or reels
            - "posting" if they are creating/uploading content

            If this is Amazon, determine the specific activity:
            - "browsing" if they are browsing or perusing the Amazon website
            - "buying" if they are on the checkout page or are reviewing their cart

            If this is YouTube, determine the specific activity:
            - "watching" if they are watching videos, browsing recommended videos, or on YouTube
            If this is none of the above, respond with:
            - "other"
            
            Respond with ONLY ONE WORD from these options: messaging, scrolling, posting, browsing, buying, watching, other
            """
        } else if appInfo.bundleIdentifier == "com.apple.MobileSMS" {
            return """
            Look at this Messages screenshot carefully.
            
            IMPORTANT: Check if you can see the name "TanTan" anywhere on the screen (in conversation list, chat header, contact name, etc.).
            
            If you see "TanTan" respond with:
            - "X"
            
            If you do NOT see that name, respond with:
            - "messaging"
            
            Respond with ONLY ONE WORD: X or messaging
            """
        } else {
            return """
            Look at this screenshot of the \(appInfo.localizedName ?? "application") app and identify what the user is doing.
            
            Respond with ONE WORD describing the activity:
            - "productive" for work-related activities
            - "browsing" for looking through products on Amazon
            - "buying" if they are on the checkout page or are reviewing their cart
            - "watching" for YouTube videos or entertainment content
            - "gaming" for games
            - "social" for social media activities  
            - "entertainment" for videos/movies
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
            let message = extractStringParameter(ruleAction.parameters["message"]) ?? 
                         "Redirecting away from potential distraction"
            let config = BrowserBackConfig(popupMessage: message)
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
}