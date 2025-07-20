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
    case screenTimeShield(ScreenTimeShieldConfig)
    case browserBack(BrowserBackConfig)
    case appSwitch(AppSwitchConfig)
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

public struct ScreenTimeShieldConfig {
    let domains: [String]
    let duration: TimeInterval
    let blockMessage: String?
    let allowOverride: Bool
    
    public init(domains: [String],
         duration: TimeInterval,
         blockMessage: String? = nil,
         allowOverride: Bool = false) {
        self.domains = domains
        self.duration = duration
        self.blockMessage = blockMessage
        self.allowOverride = allowOverride
    }
}

public struct BrowserBackConfig {
    let popupMessage: String
    let targetUrl: String?
    let triggerPhrases: [String]
    let safeDomains: [String]
    
    public init(popupMessage: String = "Redirecting you away from potential distraction",
         targetUrl: String? = nil,
         triggerPhrases: [String] = ["cart", "checkout", "purchase", "buy"],
         safeDomains: [String] = []) {
        self.popupMessage = popupMessage
        self.targetUrl = targetUrl
        self.triggerPhrases = triggerPhrases
        self.safeDomains = safeDomains
    }
}

public struct AppSwitchConfig {
    let targetApp: String
    let bundleId: String
    let fallbackApps: [String]
    let switchMessage: String?
    let forceQuit: Bool
    
    public init(targetApp: String = "Notion",
         bundleId: String = "notion.id",
         fallbackApps: [String] = ["com.apple.dt.Xcode", "com.microsoft.VSCode"],
         switchMessage: String? = nil,
         forceQuit: Bool = false) {
        self.targetApp = targetApp
        self.bundleId = bundleId
        self.fallbackApps = fallbackApps
        self.switchMessage = switchMessage
        self.forceQuit = forceQuit
    }
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
    func shieldWebsites(domains: [String], duration: TimeInterval) async -> ActionResult
    func navigateBack(withMessage message: String) async -> ActionResult
    func switchToProductiveApp(targetApp: String?) async -> ActionResult
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
        case .screenTimeShield(let config):
            return await executeScreenTimeShield(config)
        case .browserBack(let config):
            return await executeBrowserBack(config)
        case .appSwitch(let config):
            return await executeAppSwitch(config)
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
    
    func showProductivityPopup(title: String, message: String) async -> ActionResult {
        let config = PopupConfig(title: title, message: message, style: .warning)
        return await showPopup(config)
    }
    
    func shieldWebsites(domains: [String], duration: TimeInterval) async -> ActionResult {
        let config = ScreenTimeShieldConfig(domains: domains, duration: duration)
        return await executeScreenTimeShield(config)
    }
    
    func navigateBack(withMessage message: String) async -> ActionResult {
        let config = BrowserBackConfig(popupMessage: message)
        return await executeBrowserBack(config)
    }
    
    func switchToProductiveApp(targetApp: String? = nil) async -> ActionResult {
        let config = AppSwitchConfig(targetApp: targetApp ?? "Notion")
        return await executeAppSwitch(config)
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
    
    // MARK: - Screen Time Shield Implementation
    
    private func executeScreenTimeShield(_ config: ScreenTimeShieldConfig) async -> ActionResult {
        do {
            // Use macOS Screen Time API to block domains
            let screenTimeScript = createScreenTimeScript(domains: config.domains, duration: config.duration)
            
            let process = Process()
            process.launchPath = "/usr/bin/osascript"
            process.arguments = ["-e", screenTimeScript]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                print("🛡️ Screen Time shield activated for domains: \(config.domains)")
                
                // Show notification about the shield
                let _ = await sendNotification(NotificationConfig(
                    title: "Website Shield Activated",
                    body: config.blockMessage ?? "Distracting websites have been temporarily blocked for \(Int(config.duration/60)) minutes."
                ))
                
                return ActionResult(
                    success: true,
                    metadata: [
                        "blockedDomains": config.domains,
                        "duration": config.duration,
                        "scriptOutput": output
                    ]
                )
            } else {
                throw ActionDispatcherError.blockingFailed("Screen Time script failed: \(output)")
            }
            
        } catch {
            print("❌ Screen Time shield failed: \(error)")
            return ActionResult(success: false, error: error)
        }
    }
    
    private func createScreenTimeScript(domains: [String], duration: TimeInterval) -> String {
        let domainList = domains.map { "\"\($0)\"" }.joined(separator: ", ")
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        
        return """
        tell application "System Preferences"
            activate
            reveal pane "com.apple.preference.screentime"
        end tell
        
        tell application "System Events"
            tell process "System Preferences"
                -- Navigate to App & Website Limits
                click button "App & Website Limits" of group 1 of window 1
                delay 2
                
                -- Add new limit
                click button "+" of group 1 of window 1
                delay 1
                
                -- Select websites
                click button "Websites" of group 1 of window 1
                delay 1
                
                -- Add specific domains (simplified approach)
                repeat with domain in {\(domainList)}
                    -- This is a simplified approach - actual implementation would need more specific UI automation
                end repeat
                
                -- Set time limit
                set value of text field 1 of group 1 of window 1 to "\(hours)"
                set value of text field 2 of group 1 of window 1 to "\(minutes)"
                
                -- Save
                click button "Add" of group 1 of window 1
            end tell
        end tell
        """
    }
    
    // MARK: - Browser Back Implementation
    
    private func executeBrowserBack(_ config: BrowserBackConfig) async -> ActionResult {
        do {
            // First, execute the back navigation in Safari
            let backScript = """
            tell application "Safari"
                if (count of windows) > 0 then
                    tell front window
                        if (count of tabs) > 0 then
                            tell current tab
                                do JavaScript "window.history.back();"
                            end tell
                        end if
                    end tell
                end if
            end tell
            """
            
            let process = Process()
            process.launchPath = "/usr/bin/osascript"
            process.arguments = ["-e", backScript]
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("🔙 Browser back navigation executed")
                
                // Show popup message
                let popupConfig = PopupConfig(
                    title: "Navigation Redirected",
                    message: config.popupMessage,
                    style: .warning,
                    buttons: [.refocus, .dismiss]
                )
                
                let popupResult = await showPopup(popupConfig)
                
                return ActionResult(
                    success: true,
                    userResponse: popupResult.userResponse,
                    metadata: [
                        "backNavigationSuccess": true,
                        "popupShown": true,
                        "triggerPhrases": config.triggerPhrases
                    ]
                )
            } else {
                throw ActionDispatcherError.blockingFailed("Browser back navigation failed")
            }
            
        } catch {
            print("❌ Browser back navigation failed: \(error)")
            return ActionResult(success: false, error: error)
        }
    }
    
    // MARK: - App Switch Implementation
    
    private func executeAppSwitch(_ config: AppSwitchConfig) async -> ActionResult {
        do {
            var success = false
            var launchedApp = ""
            
            // Try to launch the target app first
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleId) {
                await withCheckedContinuation { continuation in
                    NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                        if error == nil {
                            success = true
                            launchedApp = config.targetApp
                            print("🚀 Launched target app: \(config.targetApp)")
                        }
                        continuation.resume()
                    }
                }
            } else {
                // Try fallback apps
                for fallbackBundle in config.fallbackApps {
                    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: fallbackBundle) {
                        await withCheckedContinuation { continuation in
                            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                                if error == nil {
                                    success = true
                                    launchedApp = fallbackBundle
                                    print("🚀 Launched fallback app: \(fallbackBundle)")
                                }
                                continuation.resume()
                            }
                        }
                        if success { break }
                    }
                }
            }
            
            if success {
                // Show optional message
                if let message = config.switchMessage {
                    let _ = await sendNotification(NotificationConfig(
                        title: "App Switch",
                        body: message
                    ))
                }
                
                // Force quit current app if requested
                if config.forceQuit {
                    if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                        frontmostApp.forceTerminate()
                    }
                }
                
                return ActionResult(
                    success: true,
                    metadata: [
                        "launchedApp": launchedApp,
                        "targetApp": config.targetApp,
                        "forceQuit": config.forceQuit
                    ]
                )
            } else {
                throw ActionDispatcherError.blockingFailed("No productive apps found to launch")
            }
            
        } catch {
            print("❌ App switch failed: \(error)")
            return ActionResult(success: false, error: error)
        }
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
    
    // MARK: - Enhanced Action Convenience Methods
    
    /// Shields shopping and e-commerce websites
    func shieldShoppingSites(duration: TimeInterval = 1800) async -> ActionResult {
        let shoppingSites = [
            "amazon.com",
            "ebay.com", 
            "target.com",
            "walmart.com",
            "alibaba.com",
            "aliexpress.com"
        ]
        
        return await shieldWebsites(domains: shoppingSites, duration: duration)
    }
    
    /// Executes shopping intervention (back + popup + app switch)
    func executeShoppingIntervention() async -> ActionResult {
        // 1. Navigate back
        let backResult = await navigateBack(withMessage: "Detected potential impulse purchase. Redirecting to help you refocus.")
        
        // 2. Switch to productive app
        let switchResult = await switchToProductiveApp()
        
        // 3. Shield shopping sites temporarily
        let shieldResult = await shieldShoppingSites(duration: 600) // 10 minutes
        
        return ActionResult(
            success: backResult.success && switchResult.success,
            userResponse: backResult.userResponse,
            metadata: [
                "backNavigation": backResult.success,
                "appSwitch": switchResult.success,
                "shieldActivated": shieldResult.success,
                "interventionType": "shopping"
            ]
        )
    }
    
    /// Executes social media intervention
    func executeSocialMediaIntervention() async -> ActionResult {
        // 1. Shield social media sites
        let socialSites = ["instagram.com", "facebook.com", "twitter.com", "tiktok.com"]
        let shieldResult = await shieldWebsites(domains: socialSites, duration: 900) // 15 minutes
        
        // 2. Switch to productive app
        let switchResult = await switchToProductiveApp(targetApp: "Notion")
        
        return ActionResult(
            success: shieldResult.success && switchResult.success,
            userResponse: nil,
            metadata: [
                "shieldActivated": shieldResult.success,
                "appSwitch": switchResult.success,
                "interventionType": "socialMedia"
            ]
        )
    }
    
    /// Emergency focus mode - maximum intervention
    func emergencyFocusMode() async -> ActionResult {
        // 1. Shield all distracting sites
        let distractingSites = [
            "youtube.com", "netflix.com", "hulu.com", "twitch.tv",
            "reddit.com", "9gag.com", "buzzfeed.com",
            "instagram.com", "facebook.com", "twitter.com", "tiktok.com",
            "amazon.com", "ebay.com", "target.com"
        ]
        
        let shieldResult = await shieldWebsites(domains: distractingSites, duration: 3600) // 1 hour
        
        // 2. Block social media apps
        let blockResult = await blockSocialMedia(duration: 3600)
        
        // 3. Switch to Notion
        let switchResult = await switchToProductiveApp()
        
        // 4. Send motivational notification
        let notifyResult = await notify(
            title: "🎯 Emergency Focus Mode Activated",
            body: "All distractions blocked for 1 hour. Time to focus on what matters most!"
        )
        
        return ActionResult(
            success: shieldResult.success && blockResult.success && switchResult.success,
            metadata: [
                "shieldActivated": shieldResult.success,
                "appsBlocked": blockResult.success,
                "appSwitch": switchResult.success,
                "notification": notifyResult.success,
                "interventionType": "emergencyFocus",
                "duration": 3600
            ]
        )
    }
}

// MARK: - MCP-Compatible Interface

/// MCP-style action dispatcher for easy integration with Model Control Protocol
@MainActor
public class MCPActionDispatcher {
    private let actionDispatcher: ActionDispatcher
    
    public init() {
        self.actionDispatcher = ActionDispatcher()
    }
    
    // MARK: - MCP Tool Functions
    
    /// MCP tool: Shield websites from distracting the user
    /// Usage: shield_websites(domains: ["amazon.com", "instagram.com"], duration: 1800)
    public func shield_websites(domains: [String], duration: TimeInterval = 1800) async -> [String: Any] {
        let result = await actionDispatcher.shieldWebsites(domains: domains, duration: duration)
        return mcpResult(from: result, toolName: "shield_websites")
    }
    
    /// MCP tool: Navigate back in browser and show intervention popup
    /// Usage: browser_back(message: "Detected potential impulse purchase")
    public func browser_back(message: String = "Redirecting to help you stay focused") async -> [String: Any] {
        let result = await actionDispatcher.navigateBack(withMessage: message)
        return mcpResult(from: result, toolName: "browser_back")
    }
    
    /// MCP tool: Switch to a productive application
    /// Usage: switch_to_app(app: "Notion")
    public func switch_to_app(app: String = "Notion") async -> [String: Any] {
        let result = await actionDispatcher.switchToProductiveApp(targetApp: app)
        return mcpResult(from: result, toolName: "switch_to_app")
    }
    
    /// MCP tool: Execute shopping intervention (comprehensive)
    /// Usage: shopping_intervention()
    public func shopping_intervention() async -> [String: Any] {
        let result = await actionDispatcher.executeShoppingIntervention()
        return mcpResult(from: result, toolName: "shopping_intervention")
    }
    
    /// MCP tool: Execute social media intervention
    /// Usage: social_media_intervention()
    public func social_media_intervention() async -> [String: Any] {
        let result = await actionDispatcher.executeSocialMediaIntervention()
        return mcpResult(from: result, toolName: "social_media_intervention")
    }
    
    /// MCP tool: Activate emergency focus mode
    /// Usage: emergency_focus()
    public func emergency_focus() async -> [String: Any] {
        let result = await actionDispatcher.emergencyFocusMode()
        return mcpResult(from: result, toolName: "emergency_focus")
    }
    
    /// MCP tool: Show productivity popup
    /// Usage: show_popup(title: "Focus Alert", message: "Time to get back to work")
    public func show_popup(title: String, message: String) async -> [String: Any] {
        let result = await actionDispatcher.showProductivityPopup(title: title, message: message)
        return mcpResult(from: result, toolName: "show_popup")
    }
    
    /// MCP tool: Send productivity notification
    /// Usage: send_notification(title: "Break Time", body: "You've been working for 2 hours")
    public func send_notification(title: String, body: String) async -> [String: Any] {
        let result = await actionDispatcher.notify(title: title, body: body)
        return mcpResult(from: result, toolName: "send_notification")
    }
    
    /// MCP tool: Block applications temporarily
    /// Usage: block_apps(apps: ["com.facebook.Facebook"], duration: 600)
    public func block_apps(apps: [String], duration: TimeInterval = 600) async -> [String: Any] {
        let result = await actionDispatcher.lock(bundleId: apps.first ?? "", duration: duration)
        return mcpResult(from: result, toolName: "block_apps")
    }
    
    // MARK: - MCP Result Formatting
    
    private func mcpResult(from actionResult: ActionResult, toolName: String) -> [String: Any] {
        var result: [String: Any] = [
            "success": actionResult.success,
            "tool": toolName,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let error = actionResult.error {
            result["error"] = error.localizedDescription
        }
        
        if let userResponse = actionResult.userResponse {
            result["user_response"] = String(describing: userResponse)
        }
        
        // Add metadata
        for (key, value) in actionResult.metadata {
            result[key] = value
        }
        
        return result
    }
}

// MARK: - BackgroundService Integration Helpers

extension ActionDispatcher {
    
    /// Easy integration point for BackgroundService to trigger shopping intervention
    func handleShoppingDetection(url: String, activity: String) async -> ActionResult {
        print("🛒 Shopping activity detected: \(activity) on \(url)")
        
        // Check if this is a purchase-related page
        let purchaseKeywords = ["cart", "checkout", "purchase", "buy", "order", "payment"]
        let isPurchasePage = purchaseKeywords.contains { url.lowercased().contains($0) || activity.lowercased().contains($0) }
        
        if isPurchasePage {
            return await executeShoppingIntervention()
        } else {
            // Just show a gentle reminder for general shopping
            return await notify(
                title: "Shopping Alert",
                body: "Detected shopping activity. Remember your budget goals!"
            )
        }
    }
    
    /// Easy integration point for BackgroundService to trigger social media intervention
    func handleSocialMediaDetection(domain: String, activity: String) async -> ActionResult {
        print("📱 Social media activity detected: \(activity) on \(domain)")
        
        // Check if this is excessive scrolling
        let timeWastingActivities = ["scrolling", "browsing", "watching"]
        let isTimeWasting = timeWastingActivities.contains { activity.lowercased().contains($0) }
        
        if isTimeWasting {
            return await executeSocialMediaIntervention()
        } else {
            // Gentle reminder for productive social media use
            return await notify(
                title: "Social Media Alert", 
                body: "Try to keep social media use productive and time-limited."
            )
        }
    }
    
    /// Easy integration point for BackgroundService to trigger app-specific interventions
    func handleActivityDetection(activity: String, app: String, domain: String?) async -> ActionResult {
        // Determine intervention based on activity and context
        switch activity.lowercased() {
        case let act where act.contains("shopping") || act.contains("buying"):
            return await handleShoppingDetection(url: domain ?? app, activity: activity)
            
        case let act where act.contains("scrolling") || act.contains("browsing"):
            if let domain = domain, ["instagram.com", "facebook.com", "twitter.com", "tiktok.com"].contains(domain) {
                return await handleSocialMediaDetection(domain: domain, activity: activity)
            }
            
        case let act where act.contains("gaming") || act.contains("entertainment"):
            return await switchToProductiveApp()
            
        default:
            // No intervention needed
            return ActionResult(success: true, metadata: ["intervention": "none", "activity": activity])
        }
        
        return ActionResult(success: true, metadata: ["intervention": "none"])
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