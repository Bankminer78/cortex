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
        let defaultRule = CompiledRule(
            name: "Instagram Scrolling Limit",
            type: .timeWindow,
            conditions: [
                RuleCondition(field: "activity", `operator`: .equal, value: .string("instagram_scrolling"))
            ],
            timeWindow: TimeWindowConfig(durationSeconds: 10, lookbackSeconds: 15, threshold: 2),
            actions: [
                RuleAction(type: .popup, parameters: ["message": .string("You've been scrolling Instagram too long!")])
            ]
        )
        
        do {
            try ruleEngine.addRule(defaultRule)
            print("✅ Default rules configured")
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
        
        // Only process Safari for now
        guard foregroundApp.bundleIdentifier == "com.apple.Safari" else {
            print("🚫 Skipping LLM analysis - only Safari is monitored currently")
            scheduleNextCycle()
            return
        }
        
        // Capture screenshot for Safari
        do {
            let captureResult = try await screenCaptureManager.captureSafariWindow()
            
            guard let result = captureResult else {
                print("⚠️ Failed to capture Safari window")
                scheduleNextCycle()
                return
            }
            
            print("📸 Safari window captured: \(result.image.width)x\(result.image.height)")
            
            // Save debug image
            try saveDebugImage(result.image)
            
            // Process with LLM
            await processWithLLM(captureResult: result, appInfo: foregroundApp)
            
        } catch {
            print("❌ Safari screen capture failed: \(error)")
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
            
            // Extract domain if it's a browser
            let domain = extractDomain(from: captureResult.windowInfo?.title, appInfo: appInfo)
            
            // Create activity record
            let activityRecord = ActivityRecord(
                activity: activity,
                productive: productive,
                app: appInfo.localizedName ?? "Unknown",
                bundleId: appInfo.bundleIdentifier,
                domain: domain
            )
            
            // Log to database
            let recordId = try databaseManager.logActivity(activityRecord)
            print("📊 Activity logged: ID=\(recordId)")
            
            // Evaluate rules
            let violations = try await ruleEngine.evaluateRules(for: activityRecord, with: databaseManager)
            
            // Dispatch actions for violations
            await handleRuleViolations(violations)
            
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
            
            If this is NOT Instagram, respond with:
            - "not_instagram"
            
            Respond with ONLY ONE WORD from these options: messaging, scrolling, posting, not_instagram
            """
        } else {
            return """
            Look at this screenshot of the \(appInfo.localizedName ?? "application") app and identify what the user is doing.
            
            Respond with ONE WORD describing the activity:
            - "productive" for work-related activities
            - "browsing" for general browsing/reading
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
    
    private func extractDomain(from windowTitle: String?, appInfo: AppInfo) -> String? {
        guard appInfo.bundleIdentifier == "com.apple.Safari" else { return nil }
        return screenCaptureManager.extractDomain(from: windowTitle)
    }
    
    private func handleRuleViolations(_ violations: [RuleViolation]) async {
        guard let actionDispatcher = actionDispatcher else {
            print("⚠️ ActionDispatcher not initialized yet")
            return
        }
        
        for violation in violations {
            print("🚨 Processing violation: \(violation.rule.name)")
            
            for action in violation.rule.actions {
                let dispatchableAction = convertToDispatchableAction(action, violation: violation)
                let result = await actionDispatcher.dispatch(dispatchableAction)
                
                if result.success {
                    print("✅ Action executed: \(action.type)")
                } else {
                    print("❌ Action failed: \(action.type) - \(result.error?.localizedDescription ?? "unknown error")")
                }
            }
        }
    }
    
    private func convertToDispatchableAction(_ ruleAction: RuleAction, violation: RuleViolation) -> DispatchableAction {
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