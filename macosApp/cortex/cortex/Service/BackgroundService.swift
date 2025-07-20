import Foundation
import AppKit
import CoreGraphics
import Vision
import ScreenCaptureKit

@available(macOS 14.0, *)
class BackgroundService {
    
    private var timer: Timer?
    private var hasRequestedPermission = false
    
    // This will hold the user's raw goal, e.g., "stop watching youtube".
    private var userGoal: String = ""

    // This method is now simpler. It just takes the raw goal string.
    func configure(with goal: String) {
        self.userGoal = goal
        print("Background service configured with goal: \(self.userGoal)")
    }

    func start() {
        stop()
        
        // Request permission once at startup
        Task {
            await requestScreenCapturePermission()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performTasks()
        }
    }
    
    private func requestScreenCapturePermission() async {
        do {
            // Request permission for screen capture explicitly
            if #available(macOS 14.0, *) {
                // First check if we can get shareable content
                let content = try await SCShareableContent.current
                print("✅ Screen capture permission granted - found \(content.displays.count) displays")
                
                // Try a small test capture to verify permission really works
                if let display = content.displays.first {
                    let config = SCStreamConfiguration()
                    config.width = 100
                    config.height = 100
                    
                    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                    let testImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    print("✅ Test capture successful - TCC permission verified")
                }
            }
        } catch {
            print("⚠️ Screen capture permission error: \(error)")
            print("Please grant Screen Recording permission in System Preferences > Privacy & Security")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func performTasks() {
        guard !userGoal.isEmpty else {
            print("No goal set. Skipping task.")
            return
        }
        
        Task {
            await checkAndProcessFocusedWindow()
        }
    }
    
    // MARK: - Window Monitoring
    
    private func getFrontmostApp() -> NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }
    
    private func isSafariInFocus() -> Bool {
        guard let app = getFrontmostApp(),
              let bundleId = app.bundleIdentifier else { return false }
        return bundleId == "com.apple.Safari"
    }
    
    
    private func checkAndProcessFocusedWindow() async {
        guard isSafariInFocus() else {
            print("🔍 Safari not in focus, skipping...")
            return
        }
        
        print("🎯 Safari detected in focus - capturing screenshot...")
        
        // Use ScreenCaptureKit directly to find and capture Safari windows
        if let screenshot = await captureSafariWindows() {
            print("📸 Safari screenshot captured")
            // COMMENTED OUT: LLM call while debugging grey screen issue
            await performMultimodalInference(on: screenshot)
            
            // Save for debugging
            saveImageForDebugging(screenshot)
        } else {
            print("⚠️ Failed to capture Safari windows")
        }
    }

    private func captureSafariWindows() async -> CGImage? {
        // Use the same approach as CaptureSafari.swift
        guard let app = getFrontmostApp(),
              let windowID = getForegroundWindowID(for: app.processIdentifier) else {
            print("⚠️ Could not get Safari window ID")
            return nil
        }
        
        print("🎯 Found Safari window ID: \(windowID)")
        
        do {
            let content = try await SCShareableContent.current
            
            // Find the specific window by ID
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                print("⚠️ Window not found in ScreenCaptureKit content")
                return nil
            }
            
            print("📐 Window frame: \(window.frame)")
            
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)
            config.capturesAudio = false
            
            let filter = SCContentFilter(desktopIndependentWindow: window)
            
            let screenshot = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            
            return screenshot
        } catch {
            print("⚠️ Safari capture error: \(error)")
            return nil
        }
    }
    
    private func getForegroundWindowID(for pid: pid_t) -> CGWindowID? {
        guard let infoList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] else { return nil }

        for dict in infoList {
            guard let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = dict[kCGWindowAlpha as String] as? Double,
                  alpha > 0,
                  let bounds = dict[kCGWindowBounds as String] as? [String: Any],
                  let width  = bounds["Width"]  as? Double,
                  let height = bounds["Height"] as? Double,
                  width  > 400, height > 300,
                  let windowID = dict[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            print("🎯 Found foreground window: ID=\(windowID), size=\(width)x\(height)")
            return windowID
        }
        return nil
    }
    
    
    // --- Multimodal Inference ---
    // This function prepares the prompt and calls Ollama LLaMA3
    private func performMultimodalInference(on image: CGImage) async {
        // 1. Create prompt that asks LLM to identify specific unproductive activities
        let textPrompt = """
        Analyze this screenshot and determine if the user is engaged in unproductive activity. 
        
        Look specifically for:
        - Social media (Instagram, Facebook, Twitter, TikTok)
        - Video streaming (YouTube, Netflix, etc.)
        - Gaming websites or apps
        - News browsing for extended periods
        - Shopping websites
        
        Respond in this format:
        ACTIVITY: [brief description of what user is doing]
        PRODUCTIVE: [true/false]
        APP: [name of app/website if identifiable]
        
        If unproductive, also include:
        POPUP_NEEDED: true
        """
        
        // 2. Call OpenRouter API
        await callOpenRouterAPI(image: image, prompt: textPrompt)
    }

    // COMMENTED OUT: Ollama implementation
    /*
    private func callOllamaAPI(image: CGImage, prompt: String) async {
        // Image debugging removed to avoid permission issues
        
        // Convert CGImage to base64
        guard let base64Image = convertImageToBase64(image) else {
            print("⚠️ Failed to convert image to base64")
            return
        }
        
        // Log image info
        print("📸 Image captured: \(image.width)x\(image.height) pixels")
        print("📦 Base64 length: \(base64Image.count) characters")
        print("📦 Base64 preview: \(String(base64Image.prefix(100)))...")
        
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": "llama3.1:8b",
            "prompt": prompt,
            "images": [base64Image],
            "stream": false
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
            
            print("🚀 Sending request to Ollama...")
            print("📝 Prompt: \(prompt)")
            print("📊 Request body size: \(jsonData.count) bytes")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 LLM API Response Status: \(httpResponse.statusCode)")
                
                // Log response headers
                for (key, value) in httpResponse.allHeaderFields {
                    print("📋 Header: \(key): \(value)")
                }
            }
            
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Raw response length: \(data.count) bytes")
                print("📥 Raw response: \(responseString)")
            }
            
            if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ Successfully parsed JSON response")
                
                if let responseText = jsonResponse["response"] as? String {
                    print("🤖 LLM Response: \(responseText)")
                    
                    if responseText.isEmpty {
                        print("⚠️ LLM returned empty response - image might not be processed")
                    }
                    
                    // Check if response indicates goal violation
                    if responseText.lowercased().contains("violation") || 
                       responseText.lowercased().contains("distracted") ||
                       responseText.lowercased().contains("youtube") ||
                       responseText.lowercased().contains("social media") {
                        await MainActor.run {
                            self.triggerUserAction(reason: "Potential goal violation detected")
                        }
                    }
                } else {
                    print("⚠️ No 'response' field in JSON")
                    print("🔍 Available JSON keys: \(jsonResponse.keys)")
                }
                
                // Log any error fields
                if let error = jsonResponse["error"] as? String {
                    print("❌ Ollama error: \(error)")
                }
                
            } else {
                print("❌ Failed to parse response as JSON")
            }
            
        } catch {
            print("⚠️ LLM API call failed: \(error)")
        }
    }
    */
    
    private func callOpenRouterAPI(image: CGImage, prompt: String) async {
        // Save image for debugging to temp directory to avoid permission issues
        saveImageForDebugging(image)
        
        // Convert CGImage to base64
        guard let base64Image = convertImageToBase64(image) else {
            print("⚠️ Failed to convert image to base64")
            return
        }
        
        // Log image info
        print("📸 Image captured: \(image.width)x\(image.height) pixels")
        print("📦 Base64 length: \(base64Image.count) characters")
        print("📦 Base64 preview: \(String(base64Image.prefix(100)))...")
        
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Load API key from environment
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? loadEnvVariable("OPENROUTER_API_KEY") else {
            print("❌ OPENROUTER_API_KEY not found in environment")
            return
        }
        
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let payload: [String: Any] = [
            "model": "openai/gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
            
            print("🚀 Sending request to OpenRouter...")
            print("📝 Prompt: \(prompt)")
            print("📊 Request body size: \(jsonData.count) bytes")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 OpenRouter API Response Status: \(httpResponse.statusCode)")
            }
            
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Raw response length: \(data.count) bytes")
                print("📥 Raw response: \(responseString)")
            }
            
            if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ Successfully parsed JSON response")
                
                // Parse OpenAI-style response format
                if let choices = jsonResponse["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    print("🤖 LLM Response: \(content)")
                    
                    if content.isEmpty {
                        print("⚠️ LLM returned empty response")
                    }
                    
                    // Parse the structured response and check for popup trigger
                    await parseActivityResponse(content)
                } else {
                    print("⚠️ No valid response content found")
                    print("🔍 Available JSON keys: \(jsonResponse.keys)")
                }
                
                if let error = jsonResponse["error"] as? [String: Any] {
                    print("❌ OpenRouter error: \(error)")
                }
                
            } else {
                print("❌ Failed to parse response as JSON")
            }
            
        } catch {
            print("⚠️ OpenRouter API call failed: \(error)")
        }
    }
    
    private func saveImageForDebugging(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("⚠️ Failed to create PNG data for debugging")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        // Save to Downloads for easy access
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent("cortex_debug_\(timestamp).png")
        
        do {
            try data.write(to: fileURL)
            print("💾 Debug image saved: \(fileURL.path)")
        } catch {
            print("⚠️ Failed to save debug image: \(error)")
        }
    }
    
    private func convertImageToBase64(_ image: CGImage) -> String? {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return data.base64EncodedString()
    }
    
    private func loadEnvVariable(_ key: String) -> String? {
        // Try to load from .env file in the app bundle or project directory
        let possiblePaths = [
            Bundle.main.path(forResource: ".env", ofType: nil),
            "/Users/niranjanbaskaran/git/cortex/macosApp/cortex/.env"
        ]
        
        for path in possiblePaths {
            guard let envPath = path,
                  let envContent = try? String(contentsOfFile: envPath) else { continue }
            
            for line in envContent.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: "=")
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == key {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
    
    private func parseActivityResponse(_ response: String) async {
        let lines = response.components(separatedBy: .newlines)
        var activity = ""
        var isProductive = true
        var appName = ""
        var popupNeeded = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ACTIVITY:") {
                activity = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("PRODUCTIVE:") {
                let productiveStr = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                isProductive = productiveStr.lowercased() == "true"
            } else if trimmed.hasPrefix("APP:") {
                appName = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("POPUP_NEEDED:") {
                let popupStr = String(trimmed.dropFirst(13)).trimmingCharacters(in: .whitespaces)
                popupNeeded = popupStr.lowercased() == "true"
            }
        }
        
        print("🔍 Activity Analysis:")
        print("   Activity: \(activity)")
        print("   Productive: \(isProductive)")
        print("   App: \(appName)")
        print("   Popup needed: \(popupNeeded)")
        
        if !isProductive && popupNeeded {
            await MainActor.run {
                self.showProductivityPopup(activity: activity, appName: appName)
            }
        }
    }
    
    private func showProductivityPopup(activity: String, appName: String) {
        print("🚨 SHOWING PRODUCTIVITY POPUP")
        
        let alert = NSAlert()
        alert.messageText = "Productivity Alert"
        alert.informativeText = "You appear to be \(activity.lowercased()) in \(appName). Consider returning to your productive work."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "I'll refocus")
        alert.addButton(withTitle: "5 more minutes")
        
        // Show popup on main thread
        DispatchQueue.main.async {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                print("✅ User chose to refocus")
            } else {
                print("⏱️ User requested 5 more minutes")
            }
        }
    }
    
    private func triggerUserAction(reason: String) {
        DispatchQueue.main.async {
            print("🚨 TRIGGERING USER ACTION: \(reason)")
            // Fallback for non-structured responses
            self.showProductivityPopup(activity: "unproductive activity", appName: "unknown app")
        }
    }
}
