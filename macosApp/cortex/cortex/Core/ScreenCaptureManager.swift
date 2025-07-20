import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics

// MARK: - App Information Types

public struct AppInfo {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t
    let isActive: Bool
}

public struct WindowInfo {
    let windowID: CGWindowID
    let frame: CGRect
    let title: String?
    let ownerApp: AppInfo
}

public struct CaptureResult {
    let image: CGImage
    let windowInfo: WindowInfo?
    let timestamp: Date
}

// MARK: - ScreenCaptureManager Protocol

public protocol ScreenCaptureManagerProtocol {
    func requestPermissions() async throws
    func getForegroundApp() -> AppInfo?
    func captureScreen() async throws -> CaptureResult
    func captureWindow(bundleId: String) async throws -> CaptureResult?
    func captureSpecificWindow(windowId: CGWindowID) async throws -> CaptureResult?
    func getAllWindows() -> [WindowInfo]
    func saveImage(_ image: CGImage, to directory: URL?, withPrefix prefix: String) throws -> URL
}

// MARK: - ScreenCaptureManager Implementation

@available(macOS 14.0, *)
class ScreenCaptureManager: ScreenCaptureManagerProtocol {
    
    private var hasRequestedPermissions = false
    
    // MARK: - Permissions
    
    func requestPermissions() async throws {
        guard !hasRequestedPermissions else { return }
        
        do {
            // Request screen capture permission
            let content = try await SCShareableContent.current
            print("✅ Screen capture permission granted - found \(content.displays.count) displays")
            
            // Verify with a test capture
            if let display = content.displays.first {
                let config = SCStreamConfiguration()
                config.width = 100
                config.height = 100
                
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                print("✅ Test capture successful - permissions verified")
            }
            
            hasRequestedPermissions = true
        } catch {
            print("❌ Screen capture permission error: \(error)")
            throw CaptureError.permissionDenied
        }
    }
    
    // MARK: - App Information
    
    func getForegroundApp() -> AppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        return AppInfo(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            processIdentifier: app.processIdentifier,
            isActive: true
        )
    }
    
    func getAllWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        
        var windows: [WindowInfo] = []
        
        for windowDict in windowList {
            guard let windowID = windowDict[kCGWindowNumber as String] as? CGWindowID,
                  let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = windowDict[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double,
                  let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 100, height > 100 else { // Filter out tiny windows
                continue
            }
            
            let frame = CGRect(x: x, y: y, width: width, height: height)
            let title = windowDict[kCGWindowName as String] as? String
            
            // Get app info for this window
            let runningApp = NSRunningApplication(processIdentifier: ownerPID)
            let appInfo = AppInfo(
                bundleIdentifier: runningApp?.bundleIdentifier,
                localizedName: runningApp?.localizedName,
                processIdentifier: ownerPID,
                isActive: runningApp?.isActive ?? false
            )
            
            let windowInfo = WindowInfo(
                windowID: windowID,
                frame: frame,
                title: title,
                ownerApp: appInfo
            )
            
            windows.append(windowInfo)
        }
        
        return windows
    }
    
    // MARK: - Screen Capture
    
    func captureScreen() async throws -> CaptureResult {
        let content = try await SCShareableContent.current
        
        guard let display = content.displays.first else {
            throw CaptureError.noDisplaysFound
        }
        
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.capturesAudio = false
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        print("📸 Full screen captured: \(image.width)x\(image.height)")
        
        return CaptureResult(
            image: image,
            windowInfo: nil,
            timestamp: Date()
        )
    }
    
    func captureWindow(bundleId: String) async throws -> CaptureResult? {
        // First find the app and its main window
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            print("❌ App with bundle ID \(bundleId) not found")
            return nil
        }
        
        // Get the main window for this app
        guard let windowID = getForegroundWindowID(for: app.processIdentifier) else {
            print("❌ No suitable window found for \(bundleId)")
            return nil
        }
        
        return try await captureSpecificWindow(windowId: windowID)
    }
    
    func captureSpecificWindow(windowId: CGWindowID) async throws -> CaptureResult? {
        let content = try await SCShareableContent.current
        
        // Find the window in ScreenCaptureKit content
        guard let window = content.windows.first(where: { $0.windowID == windowId }) else {
            print("❌ Window \(windowId) not found in ScreenCaptureKit content")
            return nil
        }
        
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.capturesAudio = false
        
        let filter = SCContentFilter(desktopIndependentWindow: window)
        
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        // Create window info
        let appInfo = AppInfo(
            bundleIdentifier: window.owningApplication?.bundleIdentifier,
            localizedName: window.owningApplication?.applicationName,
            processIdentifier: window.owningApplication?.processID ?? 0,
            isActive: true
        )
        
        let windowInfo = WindowInfo(
            windowID: windowId,
            frame: window.frame,
            title: window.title,
            ownerApp: appInfo
        )
        
        print("📸 Window captured: \(image.width)x\(image.height) for \(windowInfo.ownerApp.bundleIdentifier ?? "unknown")")
        
        return CaptureResult(
            image: image,
            windowInfo: windowInfo,
            timestamp: Date()
        )
    }
    
    // MARK: - Utility Methods
    
    private func getForegroundWindowID(for pid: pid_t) -> CGWindowID? {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        
        for dict in infoList {
            guard let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  layer == 0, // Main window layer
                  let alpha = dict[kCGWindowAlpha as String] as? Double,
                  alpha > 0, // Visible window
                  let bounds = dict[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 400, height > 300, // Reasonable size
                  let windowID = dict[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            print("🎯 Found foreground window: ID=\(windowID), size=\(width)x\(height)")
            return windowID
        }
        
        return nil
    }
    
    func saveImage(_ image: CGImage, to directory: URL? = nil, withPrefix prefix: String = "screenshot") throws -> URL {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.imageConversionFailed
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let targetDirectory = directory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let filename = "\(prefix)_\(timestamp).png"
        let fileURL = targetDirectory.appendingPathComponent(filename)
        
        try data.write(to: fileURL)
        
        print("💾 Image saved: \(fileURL.lastPathComponent)")
        
        return fileURL
    }
}

// MARK: - Convenience Extensions

extension ScreenCaptureManager {
    
    /// Captures the currently focused Safari window
    func captureSafariWindow() async throws -> CaptureResult? {
        return try await captureWindow(bundleId: "com.apple.Safari")
    }
    
    /// Captures the currently focused Messages window
    func captureMessagesWindow() async throws -> CaptureResult? {
        return try await captureWindow(bundleId: "com.apple.MobileSMS")
    }
    
    /// Captures any browser window (Safari, Chrome, Firefox, etc.)
    func captureBrowserWindow() async throws -> CaptureResult? {
        let browserBundleIds = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.operasoftware.Opera"
        ]
        
        for bundleId in browserBundleIds {
            if let result = try await captureWindow(bundleId: bundleId) {
                return result
            }
        }
        
        return nil
    }
    
    /// Checks if a specific app is currently in the foreground
    func isAppInForeground(bundleId: String) -> Bool {
        guard let foregroundApp = getForegroundApp() else { return false }
        return foregroundApp.bundleIdentifier == bundleId
    }
    
    /// Gets the current URL from Safari using AppleScript - much more reliable than window title parsing
    func getSafariCurrentURL() async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                tell application "Safari"
                    try
                        URL of document 1
                    on error
                        ""
                    end try
                end tell
                """
                
                var error: NSDictionary?
                if let scriptObject = NSAppleScript(source: script) {
                    let output = scriptObject.executeAndReturnError(&error)
                    
                    if let error = error {
                        print("🔍 AppleScript Error: \(error)")
                        continuation.resume(returning: nil)
                    } else {
                        let urlString = output.stringValue ?? ""
                        print("🔍 Safari URL from AppleScript: '\(urlString)'")
                        continuation.resume(returning: urlString.isEmpty ? nil : urlString)
                    }
                } else {
                    print("🔍 Failed to create AppleScript")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Extracts domain from a full URL string
    func extractDomainFromURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else {
            print("🔍 Invalid URL: '\(urlString)'")
            return nil
        }
        
        var domain = url.host?.lowercased()
        
        // Strip "www." prefix for consistent matching
        if let unwrappedDomain = domain, unwrappedDomain.hasPrefix("www.") {
            domain = String(unwrappedDomain.dropFirst(4))
        }
        
        print("🔍 Extracted domain: '\(domain ?? "nil")' from URL: '\(urlString)'")
        return domain
    }
    
    /// Legacy method - kept for compatibility but now uses AppleScript for Safari
    @available(*, deprecated, message: "Use getSafariCurrentURL() and extractDomainFromURL() instead")
    func extractDomain(from windowTitle: String?) -> String? {
        print("🔍 Legacy extractDomain called - consider upgrading to getSafariCurrentURL()")
        
        guard let title = windowTitle else { 
            print("🔍 Domain Debug - No window title provided")
            return nil 
        }
        
        print("🔍 Domain Debug - Window title: '\(title)'")
        
        // Try title-based detection for popular sites as fallback
        let titleMappings: [String: String] = [
            "YouTube": "youtube.com",
            "Instagram": "instagram.com", 
            "Facebook": "facebook.com",
            "Twitter": "twitter.com",
            "Amazon": "amazon.com",
            "Netflix": "netflix.com",
            "Reddit": "reddit.com",
            "TikTok": "tiktok.com"
        ]
        
        for (siteName, domain) in titleMappings {
            if title.lowercased().contains(siteName.lowercased()) {
                print("🔍 Domain Debug - Detected '\(domain)' from title containing '\(siteName)'")
                return domain
            }
        }
        
        print("🔍 Domain Debug - No domain found in title")
        return nil
    }
}

// MARK: - Error Types

enum CaptureError: Error, LocalizedError {
    case permissionDenied
    case noDisplaysFound
    case windowNotFound
    case imageConversionFailed
    case captureTimeout
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen capture permission denied"
        case .noDisplaysFound:
            return "No displays found for capture"
        case .windowNotFound:
            return "Target window not found"
        case .imageConversionFailed:
            return "Failed to convert captured image"
        case .captureTimeout:
            return "Screen capture timed out"
        }
    }
}