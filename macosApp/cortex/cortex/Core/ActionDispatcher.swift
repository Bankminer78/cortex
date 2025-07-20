import Foundation
import AppKit
import UserNotifications

// MARK: - Action Types

public enum DispatchableAction {
    case popup(PopupConfig)
    case notification(NotificationConfig)
    case block(BlockConfig)
    case webhook(WebhookConfig)
    case log(LogConfig)
    case custom(CustomActionConfig)
}

public struct PopupConfig {
    let title: String
    let message: String
    let style: PopupStyle
    let buttons: [PopupButton]
    let timeout: TimeInterval?
    let soundEnabled: Bool
    
    public init(title: String, 
         message: String, 
         style: PopupStyle = .warning, 
         buttons: [PopupButton] = [.refocus, .fiveMoreMinutes],
         timeout: TimeInterval? = nil,
         soundEnabled: Bool = true) {
        self.title = title
        self.message = message
        self.style = style
        self.buttons = buttons
        self.timeout = timeout
        self.soundEnabled = soundEnabled
    }
}

public enum PopupStyle {
    case info
    case warning
    case critical
    
    var alertStyle: NSAlert.Style {
        switch self {
        case .info: return .informational
        case .warning: return .warning
        case .critical: return .critical
        }
    }
}

public struct PopupButton {
    public let title: String
    public let action: PopupAction
    
    public init(title: String, action: PopupAction) {
        self.title = title
        self.action = action
    }
    
    public static let refocus = PopupButton(title: "I'll refocus", action: .refocus)
    public static let fiveMoreMinutes = PopupButton(title: "5 more minutes", action: .snooze(300))
    public static let doneForToday = PopupButton(title: "I'm done for today", action: .doneForToday)
    public static let dismiss = PopupButton(title: "Dismiss", action: .dismiss)
}

public enum PopupAction {
    case refocus
    case snooze(TimeInterval)
    case doneForToday
    case dismiss
    case custom(String)
}

public struct NotificationConfig {
    let title: String
    let body: String
    let identifier: String
    let categoryIdentifier: String?
    let userInfo: [String: Any]
    let soundEnabled: Bool
    let scheduleDelay: TimeInterval
    
    public init(title: String,
         body: String,
         identifier: String = UUID().uuidString,
         categoryIdentifier: String? = nil,
         userInfo: [String: Any] = [:],
         soundEnabled: Bool = true,
         scheduleDelay: TimeInterval = 0) {
        self.title = title
        self.body = body
        self.identifier = identifier
        self.categoryIdentifier = categoryIdentifier
        self.userInfo = userInfo
        self.soundEnabled = soundEnabled
        self.scheduleDelay = scheduleDelay
    }
}

public struct BlockConfig {
    let bundleIdentifiers: [String]
    let duration: TimeInterval
    let blockMessage: String?
    let allowOverride: Bool
    let whitelistApps: [String]
    
    public init(bundleIdentifiers: [String],
         duration: TimeInterval,
         blockMessage: String? = nil,
         allowOverride: Bool = false,
         whitelistApps: [String] = []) {
        self.bundleIdentifiers = bundleIdentifiers
        self.duration = duration
        self.blockMessage = blockMessage
        self.allowOverride = allowOverride
        self.whitelistApps = whitelistApps
    }
}

public struct WebhookConfig {
    let url: URL
    let method: HTTPMethod
    let headers: [String: String]
    let body: [String: Any]
    let timeout: TimeInterval
    let retryCount: Int
    
    init(url: URL,
         method: HTTPMethod = .POST,
         headers: [String: String] = [:],
         body: [String: Any],
         timeout: TimeInterval = 30,
         retryCount: Int = 3) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.retryCount = retryCount
    }
}

public enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

public struct LogConfig {
    let level: LogLevel
    let message: String
    let category: String
    let metadata: [String: Any]
    
    init(level: LogLevel = .info,
         message: String,
         category: String = "RuleViolation",
         metadata: [String: Any] = [:]) {
        self.level = level
        self.message = message
        self.category = category
        self.metadata = metadata
    }
}

public enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

public struct CustomActionConfig {
    let actionType: String
    let parameters: [String: Any]
}

// MARK: - Action Results

public struct ActionResult {
    let success: Bool
    let userResponse: PopupAction?
    let error: Error?
    let metadata: [String: Any]
    
    public init(success: Bool, userResponse: PopupAction? = nil, error: Error? = nil, metadata: [String: Any] = [:]) {
        self.success = success
        self.userResponse = userResponse
        self.error = error
        self.metadata = metadata
    }
}

// MARK: - ActionDispatcher Protocol

public protocol ActionDispatcherProtocol {
    func dispatch(_ action: DispatchableAction) async -> ActionResult
    func dispatchMultiple(_ actions: [DispatchableAction]) async -> [ActionResult]
    func registerCustomActionHandler(_ type: String, handler: @escaping (CustomActionConfig) async -> ActionResult)
    func lock(bundleId: String, duration: TimeInterval) async -> ActionResult
    func notify(title: String, body: String) async -> ActionResult
}

// MARK: - ActionDispatcher Implementation

@MainActor
class ActionDispatcher: ActionDispatcherProtocol {
    
    private var customActionHandlers: [String: (CustomActionConfig) async -> ActionResult] = [:]
    private var activeBlocks: [String: Date] = [:] // bundleId -> block end time
    private let notificationCenter = UNUserNotificationCenter.current()
    
    init() {
        setupNotificationCategories()
    }
    
    // MARK: - Public Interface
    
    func dispatch(_ action: DispatchableAction) async -> ActionResult {
        print("🎬 Dispatching action: \(action)")
        
        switch action {
        case .popup(let config):
            return await showPopup(config)
        case .notification(let config):
            return await sendNotification(config)
        case .block(let config):
            return await blockApps(config)
        case .webhook(let config):
            return await sendWebhook(config)
        case .log(let config):
            return await logMessage(config)
        case .custom(let config):
            return await executeCustomAction(config)
        }
    }
    
    func dispatchMultiple(_ actions: [DispatchableAction]) async -> [ActionResult] {
        var results: [ActionResult] = []
        
        for action in actions {
            let result = await dispatch(action)
            results.append(result)
        }
        
        return results
    }
    
    func registerCustomActionHandler(_ type: String, handler: @escaping (CustomActionConfig) async -> ActionResult) {
        customActionHandlers[type] = handler
        print("🔧 Registered custom action handler: \(type)")
    }
    
    // MARK: - Convenience Methods
    
    func lock(bundleId: String, duration: TimeInterval) async -> ActionResult {
        let config = BlockConfig(
            bundleIdentifiers: [bundleId],
            duration: duration,
            blockMessage: "This app is temporarily blocked to help you stay focused."
        )
        return await blockApps(config)
    }
    
    func notify(title: String, body: String) async -> ActionResult {
        let config = NotificationConfig(title: title, body: body)
        return await sendNotification(config)
    }
    
    // MARK: - Popup Implementation
    
    private func showPopup(_ config: PopupConfig) async -> ActionResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = config.title
                alert.informativeText = config.message
                alert.alertStyle = config.style.alertStyle
                
                // Add buttons
                for button in config.buttons {
                    alert.addButton(withTitle: button.title)
                }
                
                // Play sound if enabled
                if config.soundEnabled {
                    NSSound.beep()
                }
                
                // Show alert
                let response = alert.runModal()
                
                // Map response to action
                let buttonIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                let userAction = buttonIndex < config.buttons.count ? config.buttons[buttonIndex].action : .dismiss
                
                print("👤 User selected: \(userAction)")
                
                let result = ActionResult(
                    success: true,
                    userResponse: userAction,
                    metadata: ["buttonIndex": buttonIndex]
                )
                
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - Notification Implementation
    
    private func setupNotificationCategories() {
        let refocusAction = UNNotificationAction(
            identifier: "REFOCUS_ACTION",
            title: "I'll refocus",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "5 more minutes",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "PRODUCTIVITY_ALERT",
            actions: [refocusAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([category])
    }
    
    private func sendNotification(_ config: NotificationConfig) async -> ActionResult {
        do {
            let content = UNMutableNotificationContent()
            content.title = config.title
            content.body = config.body
            content.userInfo = config.userInfo
            
            if let categoryId = config.categoryIdentifier {
                content.categoryIdentifier = categoryId
            }
            
            if config.soundEnabled {
                content.sound = UNNotificationSound.default
            }
            
            let trigger: UNNotificationTrigger?
            if config.scheduleDelay > 0 {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: config.scheduleDelay, repeats: false)
            } else {
                trigger = nil
            }
            
            let request = UNNotificationRequest(
                identifier: config.identifier,
                content: content,
                trigger: trigger
            )
            
            try await notificationCenter.add(request)
            
            print("📱 Notification sent: \(config.title)")
            
            return ActionResult(success: true)
            
        } catch {
            print("❌ Failed to send notification: \(error)")
            return ActionResult(success: false, error: error)
        }
    }
    
    // MARK: - App Blocking Implementation
    
    private func blockApps(_ config: BlockConfig) async -> ActionResult {
        let endTime = Date().addingTimeInterval(config.duration)
        
        for bundleId in config.bundleIdentifiers {
            activeBlocks[bundleId] = endTime
            
            // Terminate the app if it's running
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.terminate()
                print("🚫 Terminated app: \(bundleId)")
            }
        }
        
        // Schedule unblock
        DispatchQueue.main.asyncAfter(deadline: .now() + config.duration) {
            for bundleId in config.bundleIdentifiers {
                self.activeBlocks.removeValue(forKey: bundleId)
                print("✅ Unblocked app: \(bundleId)")
            }
        }
        
        print("🚫 Blocked \(config.bundleIdentifiers.count) apps for \(config.duration) seconds")
        
        return ActionResult(
            success: true,
            metadata: [
                "blockedApps": config.bundleIdentifiers,
                "duration": config.duration,
                "endTime": endTime.timeIntervalSince1970
            ]
        )
    }
    
    // MARK: - Webhook Implementation
    
    private func sendWebhook(_ config: WebhookConfig) async -> ActionResult {
        do {
            var request = URLRequest(url: config.url)
            request.httpMethod = config.method.rawValue
            request.timeoutInterval = config.timeout
            
            // Set headers
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            for (key, value) in config.headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            
            // Set body
            if !config.body.isEmpty {
                request.httpBody = try JSONSerialization.data(withJSONObject: config.body)
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            
            let success = statusCode >= 200 && statusCode < 300
            
            print("🌐 Webhook sent: \(config.url) - Status: \(statusCode)")
            
            return ActionResult(
                success: success,
                metadata: [
                    "statusCode": statusCode,
                    "responseData": String(data: data, encoding: .utf8) ?? ""
                ]
            )
            
        } catch {
            print("❌ Webhook failed: \(error)")
            return ActionResult(success: false, error: error)
        }
    }
    
    // MARK: - Logging Implementation
    
    private func logMessage(_ config: LogConfig) async -> ActionResult {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] [\(config.level.rawValue)] [\(config.category)] \(config.message)"
        
        print("📝 \(logEntry)")
        
        // Write to log file
        do {
            let logsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Logs", isDirectory: true)
            
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            
            let logFile = logsDirectory.appendingPathComponent("cortex.log")
            let logData = (logEntry + "\n").data(using: .utf8)!
            
            if FileManager.default.fileExists(atPath: logFile.path) {
                let fileHandle = try FileHandle(forWritingTo: logFile)
                fileHandle.seekToEndOfFile()
                fileHandle.write(logData)
                fileHandle.closeFile()
            } else {
                try logData.write(to: logFile)
            }
            
            return ActionResult(success: true)
            
        } catch {
            print("❌ Failed to write log: \(error)")
            return ActionResult(success: false, error: error)
        }
    }
    
    // MARK: - Custom Action Implementation
    
    private func executeCustomAction(_ config: CustomActionConfig) async -> ActionResult {
        guard let handler = customActionHandlers[config.actionType] else {
            print("❌ No handler registered for custom action: \(config.actionType)")
            return ActionResult(
                success: false,
                error: ActionDispatcherError.customActionNotFound(config.actionType)
            )
        }
        
        return await handler(config)
    }
    
    // MARK: - Block Status Checking
    
    func isAppBlocked(_ bundleId: String) -> Bool {
        guard let endTime = activeBlocks[bundleId] else { return false }
        return Date() < endTime
    }
    
    func getBlockedApps() -> [String: Date] {
        return activeBlocks.filter { $0.value > Date() }
    }
}

// MARK: - Convenience Extensions

extension ActionDispatcher {
    
    /// Creates a standard Instagram scrolling popup
    func showInstagramScrollingPopup() async -> ActionResult {
        let config = PopupConfig(
            title: "Instagram Alert",
            message: "You're scrolling through Instagram. This might be taking time away from your goals.",
            style: .warning,
            buttons: [.refocus, .fiveMoreMinutes, .doneForToday]
        )
        return await showPopup(config)
    }
    
    /// Creates a productivity violation notification
    func sendProductivityAlert(app: String, activity: String) async -> ActionResult {
        let config = NotificationConfig(
            title: "Productivity Alert",
            body: "You're \(activity) in \(app). Consider returning to your productive work.",
            categoryIdentifier: "PRODUCTIVITY_ALERT"
        )
        return await sendNotification(config)
    }
    
    /// Blocks social media apps temporarily
    func blockSocialMedia(duration: TimeInterval = 300) async -> ActionResult {
        let socialMediaApps = [
            "com.facebook.Facebook",
            "com.atebits.Tweetie2", // Twitter
            "com.burbn.instagram",
            "com.zhiliaoapp.musically", // TikTok
            "com.snapchat.snapchat"
        ]
        
        let config = BlockConfig(
            bundleIdentifiers: socialMediaApps,
            duration: duration,
            blockMessage: "Social media apps are temporarily blocked to help you focus."
        )
        
        return await blockApps(config)
    }
}

// MARK: - Error Types

enum ActionDispatcherError: Error, LocalizedError {
    case customActionNotFound(String)
    case blockingFailed(String)
    case notificationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .customActionNotFound(let actionType):
            return "Custom action handler not found: \(actionType)"
        case .blockingFailed(let reason):
            return "App blocking failed: \(reason)"
        case .notificationFailed(let reason):
            return "Notification failed: \(reason)"
        }
    }
}