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
    
    private var currentProvider: LLMProvider = .openAI
    private var apiKey: String?
    
    init() {
        // Auto-configure based on available API keys
        autoConfigureProvider()
    }
    
    // MARK: - Public Interface
    
    func configure(provider: LLMProvider, apiKey: String? = nil) {
        self.currentProvider = provider
        self.apiKey = apiKey
        print("🔧 LLMClient configured for provider: \(provider)")
    }
    
    func analyze(image: CGImage, prompt: String) async throws -> LLMResponse {
        print("🤖 Starting LLM analysis with \(currentProvider)")
        
        switch currentProvider {
        case .openAI:
            return try await callOpenAI(image: image, prompt: prompt)
        case .openRouter:
            return try await callOpenRouter(image: image, prompt: prompt)
        case .local(let model):
            return try await callLocal(image: image, prompt: prompt, model: model)
        }
    }
    
    // MARK: - Provider Auto-Configuration

     private func autoConfigureProvider() {
        // Check for available API keys and configure accordingly

        if let openAIKey = getKey("OPENAI_API_KEY") {
            configure(provider: .openAI, apiKey: openAIKey)
        } else  if let openRouterKey = getKey("OPENROUTER_API_KEY") {
            configure(provider: .openRouter, apiKey: openRouterKey)
        } else {
            // Fallback to local model
            configure(provider: .local(model: "llava"))
            print("⚠️ No API keys found, falling back to local model")
        }
    
    }
    
    
    
    private func getKey(_ keyName: String) -> String? {
        // 1. Prioritize Environment Variable
        if let envKey = ProcessInfo.processInfo.environment[keyName], !envKey.isEmpty {
            print("🔑 Found API key for \(keyName) in environment variables.")
            return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Fallback to .env file bundled with the app
        if let envPath = Bundle.main.path(forResource: ".env", ofType: nil) {
            do {
                let envContent = try String(contentsOfFile: envPath, encoding: .utf8)
                let lines = envContent.components(separatedBy: .newlines)

                for line in lines {
                    // Ignore comments and empty lines
                    if line.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "#") || line.isEmpty {
                        continue
                    }

                    let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 && parts[0] == keyName {
                        print("🔑 Found API key for \(keyName) in bundled .env file.")
                        return String(parts[1])
                    }
                }
            } catch {
                print("⚠️ Could not read the bundled .env file: \(error)")
            }
        }
        
        print("❌ API key for \(keyName) not found in environment variables or bundled .env file.")
        return nil
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
        let base64Image = try convertImageToBase64(image)
        
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "images": [base64Image],
            "stream": false
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
        
        guard let content = jsonResponse?["response"] as? String else {
            throw LLMError.parseError
        }
        
        return LLMResponse(
            content: content,
            provider: .local(model: model),
            tokenUsage: nil // Local models don't report token usage
        )
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
            You are a rules engine assistant. Based on the user's goal, generate a JSON object representing a rule. The user's goal is: "\(goal)"

            The JSON must follow this structure:
            {
              "name": "A concise name for the rule based on the user's goal",
              "type": "time_window",
              "conditions": [
                { "field": "domain" | "activity", "operator": "equal", "value": "string_value" }
              ],
              "logicalOperator": "AND" | "OR",
              "timeWindow": { "durationSeconds": 1, "lookbackSeconds": 600, "threshold": 5 },
              "actions": [
                { "type": "popup" | "browser_back" | "app_switch", "parameters": { "message": "A helpful message for the user.", "targetApp": "AppName" } }
              ]
            }

            - For goals about websites (e.g., "youtube.com", "instagram.com"), use the "domain" field in lowercase.
            - For goals about actions (e.g., "scrolling", "watching", "buying"), use the "activity" field.
            - Analyze exceptions. For a goal like "don't scroll on instagram but messaging is fine", create a rule that targets `activity` == `scrolling` and `domain` == `instagram.com`, but does NOT block `messaging`.
            - Choose a sensible action: 'browser_back' for immediately stopping an action, 'popup' for warnings, and 'app_switch' to redirect to a productive app like 'Notion'.
            - Set a reasonable timeWindow. For "don't let me use X", use a short lookbackSeconds (e.g., 10) and a low threshold (e.g., 1).
            - The action 'message' should be encouraging and relate to the user's goal.

            Example Goal: "don't scroll on instagram but messaging on instagram is fine"
            Example JSON:
            {
                "name": "Limit Instagram Scrolling",
                "type": "time_window",
                "conditions": [
                    { "field": "domain", "operator": "equal", "value": "instagram.com" },
                    { "field": "activity", "operator": "equal", "value": "scrolling" }
                ],
                "logicalOperator": "AND",
                "timeWindow": { "durationSeconds": 1, "lookbackSeconds": 10, "threshold": 1 },
                "actions": [
                    { "type": "popup", "parameters": { "message": .string("You wanted to avoid scrolling on Instagram. Let's focus!") } }
                ]
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
