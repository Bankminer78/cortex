import Foundation
import AppKit
import CoreGraphics
import Vision
import ScreenCaptureKit
import SQLite3

@available(macOS 14.0, *)
class BackgroundService: @unchecked Sendable {
    
    private var timer: Timer?
    private var hasRequestedPermission = false
    private var db: OpaquePointer?
    private var isProcessingLLM = false
    
    // API Configuration - set to true for OpenAI, false for OpenRouter
    private let useOpenAI = true
    
    // This will hold the user's raw goal, e.g., "stop watching youtube".
    private var userGoal: String = ""

    // This method is now simpler. It just takes the raw goal string.
    func configure(with goal: String) {
        self.userGoal = goal
        print("Background service configured with goal: \(self.userGoal)")
    }

    func start() {
        stop()
        
        // Initialize database
        initializeDatabase()
        
        // Request permission once at startup
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
        
        // Close database connection
        if db != nil {
            sqlite3_close(db)
            db = nil
            print("📁 Database connection closed")
        }
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
        isProcessingLLM = true
        
        guard isSafariInFocus() else {
            print("🔍 Safari not in focus, skipping...")
            isProcessingLLM = false
            // Schedule next cycle after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.performTasks()
            }
            return
        }
        
        print("🎯 Safari detected in focus - capturing screenshot...")
        
        // Use ScreenCaptureKit directly to find and capture Safari windows
        if let screenshot = await captureSafariWindows() {
            print("📸 Safari screenshot captured")
            
            // Save for debugging
            saveImageForDebugging(screenshot)
            
            // Process with LLM
            await performMultimodalInference(on: screenshot)
        } else {
            print("⚠️ Failed to capture Safari windows")
            isProcessingLLM = false
            // Schedule next cycle after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.performTasks()
            }
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
        // Hardcoded prompt specifically for Instagram activity detection
        let textPrompt = """
        Look at this screenshot and identify what the user is doing. 
        
        If this is Instagram, determine the specific activity:
        - "messaging" if they are in Instagram DMs/messages talking to friends
        - "scrolling" if they are browsing the feed, stories, or reels
        - "posting" if they are creating/uploading content
        
        If this is NOT Instagram, respond with:
        - "not_instagram"
        
        Respond with ONLY ONE WORD from these options: messaging, scrolling, posting, not_instagram
        """
        
        // 2. Call LLM API (OpenAI or OpenRouter based on configuration)
        if useOpenAI {
            await callOpenAIAPI(image: image, prompt: textPrompt)
        } else {
            await callOpenRouterAPI(image: image, prompt: textPrompt)
        }
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
    
    private func callOpenAIAPI(image: CGImage, prompt: String) async {
        // Convert CGImage to base64
        guard let base64Image = convertImageToBase64(image) else {
            print("⚠️ Failed to convert image to base64")
            return
        }
        
        // Log image info
        print("📸 Image captured: \(image.width)x\(image.height) pixels")
        print("📦 Base64 length: \(base64Image.count) characters")
        print("📦 Base64 preview: \(String(base64Image.prefix(100)))...")
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Load API key from environment
        print("🔑 Checking for OpenAI API key...")
        let envApiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        print("🔑 Environment variable: \(envApiKey != nil ? "found" : "not found")")
        
        let fileApiKey = loadEnvVariable("OPENAI_API_KEY")
        print("🔑 File variable: \(fileApiKey != nil ? "found" : "not found")")
        
        guard let rawApiKey = envApiKey ?? fileApiKey else {
            print("❌ OPENAI_API_KEY not found in environment or .env file")
            return
        }
        
        // Clean the API key of any whitespace/newlines
        let apiKey = rawApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔑 Using OpenAI API key: \(String(apiKey.prefix(20)))...")
        print("🔑 API key length: \(apiKey.count)")
        
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Debug: Log all headers
        print("📋 Request headers:")
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            if key == "Authorization" {
                print("   \(key): Bearer \(String(apiKey.prefix(20)))...")
            } else {
                print("   \(key): \(value)")
            }
        }
        
        let payload: [String: Any] = [
            "model": "gpt-4o",
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
            ],
            "max_tokens": 10
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
            
            print("🚀 Sending request to OpenAI...")
            print("📝 Prompt: \(prompt)")
            print("📊 Request body size: \(jsonData.count) bytes")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 OpenAI API Response Status: \(httpResponse.statusCode)")
            }
            
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Raw response length: \(data.count) bytes")
                print("📥 Raw response: \(responseString)")
            }
            
            if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ Successfully parsed JSON response")
                
                // Parse OpenAI response format
                if let choices = jsonResponse["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    print("🤖 LLM Response: \(content)")
                    
                    if content.isEmpty {
                        print("⚠️ LLM returned empty response")
                    }
                    
                    // Parse single word Instagram activity response
                    await parseInstagramActivity(content.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    print("⚠️ No valid response content found")
                    print("🔍 Available JSON keys: \(jsonResponse.keys)")
                }
                
                if let error = jsonResponse["error"] as? [String: Any] {
                    print("❌ OpenAI error: \(error)")
                }
                
            } else {
                print("❌ Failed to parse response as JSON")
            }
            
        } catch {
            print("⚠️ OpenAI API call failed: \(error)")
        }
    }
    
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
        print("🔑 Checking for API key...")
        let envApiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        print("🔑 Environment variable: \(envApiKey != nil ? "found" : "not found")")
        
        let fileApiKey = loadEnvVariable("OPENROUTER_API_KEY")
        print("🔑 File variable: \(fileApiKey != nil ? "found" : "not found")")
        
        guard let rawApiKey = envApiKey ?? fileApiKey else {
            print("❌ OPENROUTER_API_KEY not found in environment or .env file")
            return
        }
        
        // Clean the API key of any whitespace/newlines
        let apiKey = rawApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔑 Using API key: \(String(apiKey.prefix(20)))...")
        print("🔑 API key length: \(apiKey.count)")
        
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://cortex-app.com", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Cortex", forHTTPHeaderField: "X-Title")
        
        // Debug: Log all headers
        print("📋 Request headers:")
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            if key == "Authorization" {
                print("   \(key): Bearer \(String(apiKey.prefix(20)))...")
            } else {
                print("   \(key): \(value)")
            }
        }
        
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
                    
                    // Parse single word Instagram activity response
                    await parseInstagramActivity(content.trimmingCharacters(in: .whitespacesAndNewlines))
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
        
        print("🔍 Looking for .env file in paths: \(possiblePaths)")
        
        for path in possiblePaths {
            print("🔍 Checking path: \(path ?? "nil")")
            guard let envPath = path,
                  let envContent = try? String(contentsOfFile: envPath) else { 
                print("🔍 Path not found or unreadable")
                continue 
            }
            
            print("🔍 Found .env file, content preview: \(String(envContent.prefix(50)))...")
            
            for line in envContent.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: "=")
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == key {
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    print("🔍 Found key \(key) in .env file")
                    return value
                }
            }
        }
        print("🔍 Key \(key) not found in any .env file")
        return nil
    }
    
    private func parseInstagramActivity(_ response: String) async {
        let activity = response.lowercased()
        
        print("🔍 Instagram Activity Detection: '\(activity)'")
        
        switch activity {
        case "messaging":
            print("💬 User is messaging on Instagram - generally productive social interaction")
            await logActivityToDatabase(activity: "instagram_messaging", productive: true)
            
        case "scrolling":
            print("📱 User is scrolling Instagram - potentially unproductive")
            await logActivityToDatabase(activity: "instagram_scrolling", productive: false)
            // REMOVED: Immediate popup
            // await MainActor.run {
            //     self.showInstagramScrollingPopup()
            // }
            
        case "posting":
            print("📸 User is posting on Instagram - creative/social activity")
            await logActivityToDatabase(activity: "instagram_posting", productive: true)
            
        case "not_instagram":
            print("🌐 Not Instagram - no action needed")
            await logActivityToDatabase(activity: "other_browsing", productive: true)
            
        default:
            print("❓ Unknown activity response: \(activity)")
            await logActivityToDatabase(activity: "unknown", productive: true)
        }
        
        // After logging, check rule and schedule next cycle
        await checkScrollingRule()
        isProcessingLLM = false
        
        // Schedule next cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.performTasks()
        }
    }
    
    private func initializeDatabase() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsPath.appendingPathComponent("cortex_activity.sqlite").path
        
        print("📁 Database path: \(dbPath)")
        
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("✅ Successfully opened database")
            createActivityTable()
        } else {
            print("❌ Unable to open database")
        }
    }
    
    private func createActivityTable() {
        // Drop and recreate table to fix any corruption
        let dropTableSQL = "DROP TABLE IF EXISTS activity_log;"
        sqlite3_exec(db, dropTableSQL, nil, nil, nil)
        
        let createTableSQL = """
            CREATE TABLE activity_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                activity TEXT NOT NULL,
                productive INTEGER NOT NULL,
                app TEXT NOT NULL
            );
        """
        
        if sqlite3_exec(db, createTableSQL, nil, nil, nil) == SQLITE_OK {
            print("✅ Activity table created successfully (fresh)")
        } else {
            print("❌ Failed to create activity table")
        }
    }
    
    private func logActivityToDatabase(activity: String, productive: Bool) async {
        let timestamp = Date().timeIntervalSince1970
        
        print("🔧 About to insert: activity='\(activity)', length=\(activity.count)")
        
        // Check if database is still connected
        if db == nil {
            print("❌ Database connection is nil, reinitializing...")
            initializeDatabase()
            if db == nil {
                print("❌ Failed to reinitialize database")
                return
            }
        }
        
        let insertSQL = "INSERT INTO activity_log (timestamp, activity, productive, app) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, timestamp)
            
            // Use SQLITE_TRANSIENT to ensure SQLite makes its own copy of the string
            activity.withCString { cString in
                sqlite3_bind_text(statement, 2, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            
            sqlite3_bind_int(statement, 3, productive ? 1 : 0)
            
            "Safari".withCString { cString in
                sqlite3_bind_text(statement, 4, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                print("📊 Logged to DB: [\(activity)] productive=\(productive) at \(Date(timeIntervalSince1970: timestamp))")
                
                // Immediately verify what was inserted
                verifyLastInsert()
                logRecentActivities()
            } else {
                print("❌ Failed to insert activity, error: \(result)")
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("❌ SQLite error: \(errorMsg)")
            }
        } else {
            print("❌ Failed to prepare insert statement")
            let errorMsg = String(cString: sqlite3_errmsg(db))
            print("❌ SQLite prepare error: \(errorMsg)")
        }
        
        sqlite3_finalize(statement)
    }
    
    private func verifyLastInsert() {
        // Check if database is still connected
        guard db != nil else {
            print("❌ Database connection is nil for verification")
            return
        }
        
        let selectSQL = "SELECT activity FROM activity_log ORDER BY id DESC LIMIT 1"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                if let activityCString = sqlite3_column_text(statement, 0) {
                    let activity = String(cString: activityCString)
                    print("🔧 Verification: Last inserted activity = '\(activity)'")
                } else {
                    print("🔧 Verification: Last inserted activity is NULL")
                }
            }
        }
        sqlite3_finalize(statement)
    }
    
    private func logRecentActivities() {
        // Check if database is still connected
        guard db != nil else {
            print("❌ Database connection is nil for recent activities")
            return
        }
        
        let selectSQL = "SELECT timestamp, activity, productive FROM activity_log ORDER BY timestamp DESC LIMIT 5"
        var statement: OpaquePointer?
        
        print("📋 Recent activities in DB:")
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let timestamp = sqlite3_column_double(statement, 0)
                
                // Safely get activity string with null check
                if let activityCString = sqlite3_column_text(statement, 1) {
                    let activity = String(cString: activityCString)
                    let productive = sqlite3_column_int(statement, 2) == 1
                    
                    let date = Date(timeIntervalSince1970: timestamp)
                    let formatter = DateFormatter()
                    formatter.timeStyle = .medium
                    formatter.timeZone = TimeZone.current
                    
                    print("   \(formatter.string(from: date)): \(activity) (\(productive ? "✅" : "❌"))")
                } else {
                    print("   [NULL activity record]")
                }
            }
        } else {
            print("❌ Failed to prepare select statement")
        }
        
        sqlite3_finalize(statement)
    }
    
    private func checkScrollingRule() async {
        let currentTime = Date().timeIntervalSince1970
        let tenSecondsAgo = currentTime - 10.0
        
        print("🔍 Checking rule: current=\(Date(timeIntervalSince1970: currentTime)), lookback=\(Date(timeIntervalSince1970: tenSecondsAgo))")
        
        // Check if database is still connected
        guard db != nil else {
            print("❌ Database connection is nil for rule check")
            return
        }
        
        let selectSQL = "SELECT activity, timestamp FROM activity_log WHERE timestamp >= ? ORDER BY timestamp DESC"
        var statement: OpaquePointer?
        
        var recentActivities: [String] = []
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, tenSecondsAgo)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let activityCString = sqlite3_column_text(statement, 0) {
                    let activity = String(cString: activityCString)
                    let timestamp = sqlite3_column_double(statement, 1)
                    let date = Date(timeIntervalSince1970: timestamp)
                    
                    print("🔍 Found recent activity: '\(activity)' at \(date)")
                    recentActivities.append(activity)
                } else {
                    print("🔍 Found NULL activity in database")
                }
            }
        } else {
            print("❌ Failed to prepare rule check statement")
        }
        
        sqlite3_finalize(statement)
        
        print("🔍 Activities in past 10 seconds: \(recentActivities)")
        print("🔍 Total count: \(recentActivities.count)")
        
        // Check if all recent activities are scrolling
        let scrollingActivities = recentActivities.filter { $0 == "instagram_scrolling" }
        let allScrolling = !recentActivities.isEmpty && scrollingActivities.count == recentActivities.count
        
        print("🔍 Scrolling activities: \(scrollingActivities.count)/\(recentActivities.count)")
        
        if allScrolling && recentActivities.count >= 2 {
            print("🚨 Rule triggered: User has been scrolling Instagram for past 10 seconds!")
            await MainActor.run {
                self.showInstagramScrollingPopup()
            }
        } else {
            print("✅ Rule not triggered: allScrolling=\(allScrolling), count=\(recentActivities.count)")
        }
    }
    
    private func showInstagramScrollingPopup() {
        print("🚨 SHOWING INSTAGRAM SCROLLING POPUP")
        
        let alert = NSAlert()
        alert.messageText = "Instagram Alert"
        alert.informativeText = "You're scrolling through Instagram. This might be taking time away from your goals."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "I'll refocus")
        alert.addButton(withTitle: "5 more minutes")
        alert.addButton(withTitle: "I'm done for today")
        
        // Show popup on main thread
        DispatchQueue.main.async {
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                print("✅ User chose to refocus")
            case .alertSecondButtonReturn:
                print("⏱️ User requested 5 more minutes")
            case .alertThirdButtonReturn:
                print("🛑 User is done for today")
            default:
                print("❓ Unknown response")
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
