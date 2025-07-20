import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit

// MARK: - CortexSDK Main Interface

@available(macOS 14.0, *)
public class CortexSDK {
    
    // MARK: - Core Components
    
    public let llmClient: LLMClientProtocol
    public let databaseManager: DatabaseManagerProtocol
    public let screenCaptureManager: ScreenCaptureManagerProtocol
    public let ruleEngine: RuleEngineProtocol
    public var actionDispatcher: ActionDispatcherProtocol!
    
    // MARK: - Configuration
    
    public struct Configuration {
        public let databasePath: String?
        public let llmProvider: LLMProvider?
        public let apiKey: String?
        
        public init(databasePath: String? = nil, 
                   llmProvider: LLMProvider? = nil, 
                   apiKey: String? = nil) {
            self.databasePath = databasePath
            self.llmProvider = llmProvider
            self.apiKey = apiKey
        }
    }
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = Configuration()) throws {
        // Initialize core components
        self.databaseManager = try DatabaseManager()
        self.llmClient = LLMClient()
        self.screenCaptureManager = ScreenCaptureManager()
        self.ruleEngine = RuleEngine()
        
        // Initialize action dispatcher on main actor
        Task { @MainActor in
            self.actionDispatcher = ActionDispatcher()
        }
        
        // Configure components if specified
        if let provider = configuration.llmProvider {
            self.llmClient.configure(provider: provider, apiKey: configuration.apiKey)
        }
    }
    
    // MARK: - High-Level API
    
    /// Monitors screen activity and triggers rules
    public func startMonitoring(with goal: String) throws {
        let backgroundService = try BackgroundService()
        backgroundService.configure(with: goal)
        backgroundService.start()
    }
    
    /// Analyzes a screenshot and returns activity classification
    public func analyzeActivity(image: CGImage, prompt: String? = nil) async throws -> String {
        let defaultPrompt = prompt ?? """
            Look at this screenshot and identify what the user is doing.
            Respond with ONE WORD describing the activity:
            - "productive" for work-related activities
            - "browsing" for general browsing/reading
            - "gaming" for games
            - "social" for social media activities  
            - "entertainment" for videos/movies
            - "other" for anything else
            """
        
        let response = try await llmClient.analyze(image: image, prompt: defaultPrompt)
        return response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
    }
    
    /// Captures the current foreground window
    public func captureCurrentWindow() async throws -> CaptureResult? {
        guard let foregroundApp = screenCaptureManager.getForegroundApp() else {
            throw CortexSDKError.noForegroundApp
        }
        
        return try await screenCaptureManager.captureWindow(bundleId: foregroundApp.bundleIdentifier ?? "")
    }
    
    /// Adds a natural language rule
    public func addRule(name: String, naturalLanguage: String) async throws {
        let compiledRule = try await ruleEngine.compileRule(from: naturalLanguage, using: llmClient)
        try ruleEngine.addRule(compiledRule)
    }
    
    /// Gets all active rules
    public func getRules() -> [CompiledRule] {
        return ruleEngine.getRules()
    }
    
    /// Logs an activity to the database
    public func logActivity(activity: String, app: String, productive: Bool, bundleId: String? = nil) throws -> Int {
        let record = ActivityRecord(
            activity: activity,
            productive: productive,
            app: app,
            bundleId: bundleId
        )
        return try databaseManager.logActivity(record)
    }
    
    /// Gets recent activities from the database
    public func getRecentActivities(limit: Int = 10) throws -> [ActivityRecord] {
        return try databaseManager.getRecentActivities(limit: limit)
    }
    
    /// Shows a productivity popup
    public func showProductivityPopup(title: String, message: String) async -> ActionResult {
        guard let actionDispatcher = actionDispatcher else {
            return ActionResult(success: false, error: CortexSDKError.componentNotInitialized("ActionDispatcher"))
        }
        let config = PopupConfig(title: title, message: message, style: .warning)
        return await actionDispatcher.dispatch(.popup(config))
    }
    
    /// Sends a notification
    public func sendNotification(title: String, body: String) async -> ActionResult {
        guard let actionDispatcher = actionDispatcher else {
            return ActionResult(success: false, error: CortexSDKError.componentNotInitialized("ActionDispatcher"))
        }
        return await actionDispatcher.notify(title: title, body: body)
    }
    
    /// Blocks an app temporarily
    public func blockApp(bundleId: String, duration: TimeInterval) async -> ActionResult {
        guard let actionDispatcher = actionDispatcher else {
            return ActionResult(success: false, error: CortexSDKError.componentNotInitialized("ActionDispatcher"))
        }
        return await actionDispatcher.lock(bundleId: bundleId, duration: duration)
    }
}

// MARK: - Convenience Extensions

@available(macOS 14.0, *)
public extension CortexSDK {
    
    /// Monitors Instagram usage and shows popup after excessive scrolling
    func monitorInstagramUsage() throws {
        let rule = CompiledRule(
            name: "Instagram Scrolling Monitor",
            type: .timeWindow,
            conditions: [
                RuleCondition(field: "activity", `operator`: .equal, value: .string("scrolling")),
                RuleCondition(field: "domain", `operator`: .equal, value: .string("instagram.com"))
            ],
            logicalOperator: .and,
            timeWindow: TimeWindowConfig(durationSeconds: 300, lookbackSeconds: 600, threshold: 1),
            actions: [
                RuleAction(type: .popup, parameters: [
                    "message": .string("You've been scrolling Instagram for 5 minutes. Time to refocus!")
                ])
            ]
        )
        
        try ruleEngine.addRule(rule)
    }
    
    /// Blocks social media during work hours
    func blockSocialMediaDuringWork() throws {
        let rule = CompiledRule(
            name: "Work Hours Social Media Block",
            type: .schedule,
            conditions: [
                RuleCondition(field: "app", `operator`: .equal, value: .string("Safari"))
            ],
            scheduleConfig: ScheduleConfig(
                startTime: "09:00",
                endTime: "17:00",
                daysOfWeek: [1, 2, 3, 4, 5], // Monday to Friday
                timezone: nil
            ),
            actions: [
                RuleAction(type: .block, parameters: [
                    "duration": .double(300)
                ])
            ]
        )
        
        try ruleEngine.addRule(rule)
    }
    
    /// Gets productivity statistics for today
    func getTodayProductivityStats() throws -> ProductivityStats {
        let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let now = Date().timeIntervalSince1970
        
        let activities = try databaseManager.getActivitiesInTimeRange(from: startOfDay, to: now)
        
        let productiveCount = activities.filter { $0.productive }.count
        let unproductiveCount = activities.count - productiveCount
        let totalTime = now - startOfDay
        
        return ProductivityStats(
            totalActivities: activities.count,
            productiveActivities: productiveCount,
            unproductiveActivities: unproductiveCount,
            productivityRatio: Double(productiveCount) / Double(activities.count),
            totalTimeTracked: totalTime
        )
    }
}

// MARK: - Data Models

public struct ProductivityStats {
    public let totalActivities: Int
    public let productiveActivities: Int
    public let unproductiveActivities: Int
    public let productivityRatio: Double
    public let totalTimeTracked: TimeInterval
    
    public var productivityPercentage: Double {
        return productivityRatio * 100
    }
}

// MARK: - Error Types

public enum CortexSDKError: Error, LocalizedError {
    case noForegroundApp
    case componentNotInitialized(String)
    case configurationError(String)
    
    public var errorDescription: String? {
        switch self {
        case .noForegroundApp:
            return "No foreground application detected"
        case .componentNotInitialized(let component):
            return "Component not initialized: \(component)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}

// MARK: - Global SDK Instance

@available(macOS 14.0, *)
public class Cortex {
    public static var shared: CortexSDK = {
        do {
            return try CortexSDK()
        } catch {
            fatalError("Failed to initialize CortexSDK: \(error)")
        }
    }()
    
    private init() {}
}