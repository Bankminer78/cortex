import Foundation
import CoreGraphics
import AppKit

// MARK: - LLM Provider Types

public enum LLMProvider {
    case openAI
    case openRouter
    case local(model: String)
}

public struct LLMResponse {
    let content: String
    let provider: LLMProvider
    let tokenUsage: TokenUsage?
}

public struct TokenUsage {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

// MARK: - LLMClient Protocol

public protocol LLMClientProtocol {
    func analyze(image: CGImage, prompt: String) async throws -> LLMResponse
    func configure(provider: LLMProvider, apiKey: String?)
}

// MARK: - LLMClient Implementation

@available(macOS 14.0, *)
class LLMClient: LLMClientProtocol {
    
    private var currentProvider: LLMProvider = .openRouter
    private var apiKey: String?
    private var useLocalForImages: Bool = false
    private var debugMode: Bool = false
    private var useChainOfThought: Bool = false
    
    init() {
        // Auto-configure based on available API keys and local model availability
        autoConfigureProvider()
    }
    
    // MARK: - Public Interface
    
    func configure(provider: LLMProvider, apiKey: String? = nil) {
        self.currentProvider = provider
        self.apiKey = apiKey
        print("🔧 LLMClient configured for provider: \(provider)")
    }
    
    func configureLocalImages(enabled: Bool) {
        self.useLocalForImages = enabled
        if enabled {
            print("🦙 Local Llava enabled for image analysis")
        } else {
            print("☁️ Using online providers for image analysis")
        }
    }
    
    func configureDebugMode(enabled: Bool) {
        self.debugMode = enabled
        if enabled {
            print("🔍 Debug mode enabled - will show Llava's image interpretation")
        } else {
            print("🔍 Debug mode disabled")
        }
    }
    
    func analyze(image: CGImage, prompt: String) async throws -> LLMResponse {
        // Use local Llava for image analysis if available, otherwise use configured provider
        if useLocalForImages {
            print("🦙 Using Ollama Llava for local image analysis")
            do {
                return try await callOllama(image: image, prompt: prompt, model: "llava")
            } catch {
                print("⚠️ Ollama failed, falling back to online provider: \(error)")
                useLocalForImages = false  // Disable for this session
                return try await analyze(image: image, prompt: prompt)  // Retry with online
            }
        } else {
            print("☁️ Using online provider \(currentProvider) for image analysis")
            
            switch currentProvider {
            case .openAI:
                return try await callOpenAI(image: image, prompt: prompt)
            case .openRouter:
                return try await callOpenRouter(image: image, prompt: prompt)
            case .local(let model):
                return try await callLocal(image: image, prompt: prompt, model: model)
            }
        }
    }
    
    // MARK: - Provider Auto-Configuration

     private func autoConfigureProvider() {
        // Check for available API keys and configure accordingly
        if let openAIKey = loadAPIKey("OPENAI_API_KEY") {
            configure(provider: .openAI, apiKey: openAIKey)
        } else if let openRouterKey = loadAPIKey("OPENROUTER_API_KEY") {
            configure(provider: .openRouter, apiKey: openRouterKey)
        } else {
            // Fallback to local model
            configure(provider: .local(model: "llava"))
            print("⚠️ No API keys found, falling back to local model")
        }
        
        // Check if we should use local images (from environment or auto-detect)
        if let useLocalEnv = loadAPIKey("USE_LOCAL_IMAGES"), useLocalEnv.lowercased() == "true" {
            useLocalForImages = true
            print("🦙 USE_LOCAL_IMAGES=true - enabling local Llava for image analysis")
        } else {
            // Auto-detect Ollama availability for image analysis
            Task {
                if await checkOllamaAvailability() {
                    useLocalForImages = true
                    print("🦙 Ollama detected - using local Llava for image analysis")
                }
            }
        }
        
        // Check if debug mode should be enabled
        if let debugEnv = loadAPIKey("DEBUG_LLAVA"), debugEnv.lowercased() == "true" {
            debugMode = true
            print("🔍 DEBUG_LLAVA=true - enabling Llava debug mode")
        }
        
        // Check if chain-of-thought mode should be enabled
        if let cotEnv = loadAPIKey("LLAVA_CHAIN_OF_THOUGHT"), cotEnv.lowercased() == "true" {
            useChainOfThought = true
            print("🧠 LLAVA_CHAIN_OF_THOUGHT=true - enabling thinking process")
        }
    }
    
    private func loadAPIKey(_ keyName: String) -> String? {
        // Try environment variable first
        if let envKey = ProcessInfo.processInfo.environment[keyName] {
            return envKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        
        // Try .env file
        return loadEnvVariable(keyName)
    }
    
    private func loadEnvVariable(_ key: String) -> String? {
        let possiblePaths = [
            Bundle.main.path(forResource: ".env", ofType: nil),
            "/Users/niranjanbaskaran/git/cortex/macosApp/cortex/.env"
        ]
        
        for path in possiblePaths {
            guard let envPath = path,
                  let envContent = try? String(contentsOfFile: envPath) else { continue }
            
            for line in envContent.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: "=")
                if parts.count == 2 && parts[0].trimmingCharacters(in: CharacterSet.whitespaces) == key {
                    return parts[1].trimmingCharacters(in: CharacterSet.whitespaces)
                }
            }
        }
        return nil
    }
    
    private func checkOllamaAvailability() async -> Bool {
        do {
            let url = URL(string: "http://localhost:11434/api/tags")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            // Check if Llava model is available
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                
                let hasLlava = models.contains { model in
                    if let name = model["name"] as? String {
                        return name.lowercased().contains("llava")
                    }
                    return false
                }
                
                if hasLlava {
                    print("🦙 Found Llava model in Ollama")
                    return true
                } else {
                    print("⚠️ Ollama running but no Llava model found. Run: ollama pull llava")
                    return false
                }
            }
            
            return false
        } catch {
            print("🔍 Ollama not detected on localhost:11434")
            return false
        }
    }
    
    // MARK: - OpenAI Implementation
    
    private func callOpenAI(image: CGImage, prompt: String) async throws -> LLMResponse {
        guard let apiKey = apiKey else {
            throw LLMError.missingAPIKey("OpenAI API key not found")
        }
        
        let base64Image = try convertImageToBase64(image)
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
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
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LLMError.httpError(httpResponse.statusCode)
        }
        
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let choices = jsonResponse?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError
        }
        
        let usage = extractTokenUsage(from: jsonResponse)
        
        return LLMResponse(
            content: content,
            provider: .openAI,
            tokenUsage: usage
        )
    }
    
    // MARK: - OpenRouter Implementation
    
    private func callOpenRouter(image: CGImage, prompt: String) async throws -> LLMResponse {
        guard let apiKey = apiKey else {
            throw LLMError.missingAPIKey("OpenRouter API key not found")
        }
        
        let base64Image = try convertImageToBase64(image)
        
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://cortex-app.com", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Cortex", forHTTPHeaderField: "X-Title")
        
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
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LLMError.httpError(httpResponse.statusCode)
        }
        
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let choices = jsonResponse?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError
        }
        
        let usage = extractTokenUsage(from: jsonResponse)
        
        return LLMResponse(
            content: content,
            provider: .openRouter,
            tokenUsage: usage
        )
    }
    
    // MARK: - Local Model Implementation
    
    private func callLocal(image: CGImage, prompt: String, model: String) async throws -> LLMResponse {
        // Legacy local model call - keeping for backward compatibility
        return try await callOllama(image: image, prompt: prompt, model: model)
    }
    
    // MARK: - Ollama Implementation
    
    private func callOllama(image: CGImage, prompt: String, model: String) async throws -> LLMResponse {
        let base64Image = try convertImageToBase64(image)
        
        // If debug mode is enabled, first ask Llava to describe what it sees
        if debugMode {
            let debugResponse = try await callOllamaDebug(base64Image: base64Image, model: model)
            print("🔍 LLAVA DEBUG - What Llava sees in the image:")
            print("🔍 \(debugResponse)")
            print("🔍 Now asking Llava to classify with prompt: \(prompt)")
        }
        
        // Modify prompt for chain-of-thought mode
        let finalPrompt = if useChainOfThought {
            prompt + "\n\nThink step by step: First describe what you see, then give your one-word classification at the end after 'ANSWER:'."
        } else {
            prompt
        }
        
        let url = URL(string: "http://localhost:11434/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": finalPrompt,
                    "images": [base64Image]
                ]
            ],
            "stream": false
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ Ollama HTTP Error: \(httpResponse.statusCode), Body: \(errorBody)")
            throw LLMError.httpError(httpResponse.statusCode)
        }
        
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let message = jsonResponse?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("❌ Ollama Parse Error: \(String(data: data, encoding: .utf8) ?? "No data")")
            throw LLMError.parseError
        }
        
        // Extract final answer from chain-of-thought response
        let finalContent = if useChainOfThought {
            extractAnswerFromChainOfThought(content)
        } else {
            content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Clean up escaped characters from Llava responses
        let cleanedContent = finalContent.replacingOccurrences(of: "\\_", with: "_")
        
        if debugMode {
            print("🔍 LLAVA RESPONSE: \(content)")
            if useChainOfThought {
                print("🔍 EXTRACTED ANSWER: \(finalContent)")
            }
            print("🧹 CLEANED CONTENT: \(cleanedContent)")
        }
        
        return LLMResponse(
            content: cleanedContent,
            provider: .local(model: model),
            tokenUsage: nil // Local models don't report token usage
        )
    }
    
    // Debug helper function to see what Llava thinks is in the image
    private func callOllamaDebug(base64Image: String, model: String) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let debugPrompt = "Describe what you see in this screenshot. Be detailed about any text, UI elements, apps, and activities you can identify."
        
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": debugPrompt,
                    "images": [base64Image]
                ]
            ],
            "stream": false
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return "Debug call failed"
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = jsonResponse["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return "Debug parse failed"
        }
        
        return content
    }
    
    // Extract the final answer from chain-of-thought response
    private func extractAnswerFromChainOfThought(_ content: String) -> String {
        // Look for "ANSWER:" pattern
        if let answerRange = content.range(of: "ANSWER:", options: .caseInsensitive) {
            let answerPart = String(content[answerRange.upperBound...])
            let cleanAnswer = answerPart.trimmingCharacters(in: .whitespacesAndNewlines)
            // Get just the first word after ANSWER:
            let firstWord = cleanAnswer.components(separatedBy: .whitespaces).first ?? cleanAnswer
            return firstWord.lowercased().replacingOccurrences(of: "\\_", with: "_")
        }
        
        // Fallback: try to extract the last single word from the response
        let words = content.components(separatedBy: .whitespaces)
        if let lastWord = words.last?.trimmingCharacters(in: .punctuationCharacters),
           lastWord.count < 30 { // Reasonable length for a classification
            return lastWord.lowercased().replacingOccurrences(of: "\\_", with: "_")
        }
        
        // Final fallback: return trimmed content
        return content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\\_", with: "_")
    }
    
    // MARK: - Utility Methods
    
    private func convertImageToBase64(_ image: CGImage) throws -> String {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw LLMError.imageConversionFailed
        }
        return data.base64EncodedString()
    }
    
    private func extractTokenUsage(from json: [String: Any]?) -> TokenUsage? {
        guard let usage = json?["usage"] as? [String: Any],
              let promptTokens = usage["prompt_tokens"] as? Int,
              let completionTokens = usage["completion_tokens"] as? Int,
              let totalTokens = usage["total_tokens"] as? Int else {
            return nil
        }
        
        return TokenUsage(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens
        )
    }

    func generateRuleJSON(from naturalLanguageGoal: String) async throws -> LLMResponse {
            print("🤖 Starting rule generation for goal: '\(naturalLanguageGoal)'")

            switch currentProvider {
            case .openAI:
                return try await callOpenAIForText(prompt: createRuleGenerationPrompt(for: naturalLanguageGoal))
            case .openRouter:
                // You can implement a similar text-only function for OpenRouter if needed
                print("⚠️ OpenRouter text-only generation not implemented, falling back to OpenAI method.")
                return try await callOpenAIForText(prompt: createRuleGenerationPrompt(for: naturalLanguageGoal))
            case .local:
                throw LLMError.unsupportedOperation("Rule generation is not supported for local models in this example.")
            }
        }

        private func createRuleGenerationPrompt(for goal: String) -> String {
            return """
            You are a rules engine assistant. Based on the user's goal, generate a JSON object representing a rule AND detection instructions. The user's goal is: "\(goal)"

            The JSON must follow this structure:
            {
              "name": "A concise name for the rule based on the user's goal",
              "type": "time_window",
              "conditions": [
                { "field": "domain" | "activity" | "app", "operator": "==", "value": "string_value" }
              ],
              "logicalOperator": "AND" | "OR",
              "timeWindow": { "durationSeconds": 1, "lookbackSeconds": 600, "threshold": 5 },
              "actions": [
                { "type": "popup" | "browser_back" | "close_browser_tab" | "app_switch", "parameters": { "message": "A helpful message for the user.", "targetApp": "AppName" } }
              ],
              "detectionInstructions": "Specific instructions for detecting activities related to this rule"
            }

            - For goals about websites (e.g., "youtube.com", "instagram.com"), use the "domain" field in lowercase.
            - For goals about actions, create SPECIFIC activity categories rather than generic ones. Use descriptive names like "browsing_machine_learning", "watching_music", "scrolling_instagram" instead of just "browsing", "watching", "scrolling".
            - For goals about specific apps, use the "app" field with these supported values:
              * "Safari" for web browser activities
              * "Messages" for iMessage/text messaging activities
            - Analyze exceptions. For a goal like "don't scroll on instagram but messaging is fine", create a rule that targets `activity` == `scrolling_instagram` and `domain` == `instagram.com`, but does NOT block `messaging_instagram`.
            - Choose appropriate actions based on context:
              * 'close_browser_tab' when user specifically mentions closing/removing tabs or when they want to completely stop a web activity
              * 'browser_back' for redirecting away from a page but staying in the browser
              * 'popup' for warnings and gentle reminders
              * 'app_switch' to redirect to a productive app like 'Notion'
            - Set a reasonable timeWindow. For "don't let me use X", use a short lookbackSeconds (e.g., 10) and a low threshold (e.g., 1).
            - The action 'message' should be encouraging and relate to the user's goal.
            - The detectionInstructions should provide specific visual guidance for identifying the target domain/activity in screenshots. Focus on visual elements, UI patterns, and content analysis rather than URL parsing.
            - IMPORTANT: Create unique, specific activity names that match exactly what the user wants to control. The LLM should respond with these exact category names when analyzing screenshots.

            IMPORTANT EXAMPLES:

            Example Goal: "don't scroll on instagram but messaging on instagram is fine"
            Example JSON:
            {
                "name": "Limit Instagram Scrolling",
                "type": "time_window",
                "conditions": [
                    { "field": "domain", "operator": "==", "value": "instagram.com" },
                    { "field": "activity", "operator": "==", "value": "scrolling_instagram" }
                ],
                "logicalOperator": "AND",
                "timeWindow": { "durationSeconds": 1, "lookbackSeconds": 10, "threshold": 1 },
                "actions": [
                    { "type": "popup", "parameters": { "message": "You wanted to avoid scrolling on Instagram. Let's focus!" } }
                ],
                "detectionInstructions": "Look for Instagram's distinctive visual elements: the camera icon, heart/like buttons, story circles at the top, and the characteristic grid or feed layout. If you see Instagram:\\n- Respond 'scrolling_instagram' if you see the main feed with posts, stories, or reels displayed\\n- Respond 'messaging_instagram' if you see direct message conversations with chat bubbles\\n- Respond 'posting_instagram' if you see content creation interfaces with camera/upload options"
            }

            Example Goal: "only allow r/MachineLearning subreddit on reddit"
            Example JSON:
            {
                "name": "Restrict Reddit to ML Subreddit",
                "type": "time_window", 
                "conditions": [
                    { "field": "domain", "operator": "==", "value": "reddit.com" },
                    { "field": "activity", "operator": "==", "value": "browsing_other_subreddits" }
                ],
                "logicalOperator": "AND",
                "timeWindow": { "durationSeconds": 1, "lookbackSeconds": 5, "threshold": 1 },
                "actions": [
                    { "type": "browser_back", "parameters": { "message": "Only r/MachineLearning allowed on Reddit!" } }
                ],
                "detectionInstructions": "Look for Reddit's distinctive orange/red branding and upvote/downvote arrows. If you see Reddit, examine the content and subreddit indicators:\\n- Check for 'r/MachineLearning' text in the subreddit name area\\n- Look for machine learning related posts, discussions about models, papers, datasets\\n- If you see r/MachineLearning content, respond 'browsing_machine_learning'\\n- If you see any other subreddit or non-ML content, respond 'browsing_other_subreddits'"
            }

            Example Goal: "don't watch youtube videos, only music is okay"
            Example JSON:
            {
                "name": "YouTube Music Only",
                "type": "time_window",
                "conditions": [
                    { "field": "domain", "operator": "==", "value": "youtube.com" },
                    { "field": "activity", "operator": "==", "value": "watching_videos" }
                ],
                "logicalOperator": "AND", 
                "timeWindow": { "durationSeconds": 1, "lookbackSeconds": 5, "threshold": 1 },
                "actions": [
                    { "type": "popup", "parameters": { "message": "Remember: only music on YouTube!" } }
                ],
                "detectionInstructions": "Look for YouTube's red play button and video interface. Analyze the video content and context:\\n- Respond 'watching_music' if you see music videos, album covers, artist names, music-related thumbnails, or playlists with song titles\\n- Respond 'watching_videos' if you see regular video content like vlogs, tutorials, entertainment, or non-music videos\\n- Look for visual cues like music notation, instruments, concert footage, or audio waveforms to identify music content"
            }

            Example Goal: "stop me from texting my ex in Messages"
            Example JSON:
            {
                "name": "Block Texting Ex",
                "type": "time_window",
                "conditions": [
                    { "field": "app", "operator": "==", "value": "Messages" },
                    { "field": "activity", "operator": "==", "value": "messaging_ex" }
                ],
                "logicalOperator": "AND",
                "timeWindow": { "durationSeconds": 1, "lookbackSeconds": 5, "threshold": 1 },
                "actions": [
                    { "type": "app_switch", "parameters": { "targetApp": "Notion", "message": "Redirect your energy to something positive!" } }
                ],
                "detectionInstructions": "Look for the Messages app interface with its characteristic chat bubbles and conversation layout. Check for specific contact names or conversation patterns that suggest messaging an ex-partner. Look for names, profile pictures, or conversation context that indicates personal relationships rather than professional or family messaging. Respond 'messaging_ex' if you detect messaging with romantic ex-partners, otherwise respond 'messaging_general'."
            }

            Example Goal: "close the tab when I go to shopping sites"
            Example JSON:
            {
                "name": "Close Shopping Tabs",
                "type": "time_window",
                "conditions": [
                    { "field": "activity", "operator": "==", "value": "shopping_browsing" }
                ],
                "logicalOperator": "AND",
                "timeWindow": { "durationSeconds": 1, "lookbackSeconds": 3, "threshold": 1 },
                "actions": [
                    { "type": "close_browser_tab", "parameters": { "message": "Shopping tab closed to help you save money!", "showNotification": true } }
                ],
                "detectionInstructions": "Look for e-commerce and shopping website interfaces: product listings, shopping carts, 'Add to Cart' buttons, price tags, product images, checkout pages, or payment forms. Common shopping sites include Amazon, eBay, Target, Walmart, etc. If you see shopping-related content, respond 'shopping_browsing', otherwise respond with the appropriate activity category."
            }

            Now, generate the JSON for the user's goal. Respond with ONLY the valid JSON object and nothing else.
            """
        }

        // A new private helper for text-only OpenAI calls
        private func callOpenAIForText(prompt: String) async throws -> LLMResponse {
            guard let apiKey = apiKey else {
                throw LLMError.missingAPIKey("OpenAI API key not found")
            }
            
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
            let payload: [String: Any] = [
                "model": "gpt-4o",
                "messages": [
                    [
                        "role": "user",
                        "content": prompt
                    ]
                ],
                "max_tokens": 500,
                "response_format": [ "type": "json_object" ] // Ensure the output is JSON
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                print("❌ HTTP Error: \( (response as? HTTPURLResponse)?.statusCode ?? 0), Body: \(errorBody)")
                throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
            }
            
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw LLMError.parseError
            }
            
            let usage = extractTokenUsage(from: jsonResponse)
            
            return LLMResponse(content: content, provider: .openAI, tokenUsage: usage)
        }
}

// MARK: - Error Types

enum LLMError: Error, LocalizedError {
    case missingAPIKey(String)
    case imageConversionFailed
    case invalidResponse
    case httpError(Int)
    case parseError
    case unsupportedOperation(String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let message):
            return "Missing API key: \(message)"
        case .imageConversionFailed:
            return "Failed to convert image to base64"
        case .invalidResponse:
            return "Invalid response from LLM provider"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .parseError:
            return "Failed to parse LLM response"
        case .unsupportedOperation(let message):
            return "Unsupported operation: \(message)"
        }
    }
}
