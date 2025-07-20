#!/usr/bin/env swift

import Foundation
import AppKit

func convertImageToBase64(imagePath: String) -> String? {
    guard let image = NSImage(contentsOfFile: imagePath) else {
        print("❌ Failed to load image from: \(imagePath)")
        return nil
    }
    
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("❌ Failed to convert NSImage to CGImage")
        return nil
    }
    
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("❌ Failed to convert image to PNG data")
        return nil
    }
    
    return data.base64EncodedString()
}

func testOpenRouterAPI() async {
    let imagePath = "./img.png"
    
    print("🔍 Loading image from: \(imagePath)")
    
    guard let base64Image = convertImageToBase64(imagePath: imagePath) else {
        print("❌ Failed to process image")
        return
    }
    
    print("✅ Image loaded successfully")
    print("📦 Base64 length: \(base64Image.count) characters")
    print("📦 Base64 preview: \(String(base64Image.prefix(100)))...")
    
    // OpenRouter API configuration (from openrouter.py)
    let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer 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", forHTTPHeaderField: "Authorization")
    
    // OpenRouter payload with vision-capable model
    let payload: [String: Any] = [
        "model": "openai/gpt-4o",  // Vision-capable model from openrouter.py
        "messages": [
            [
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": "Analyze this screenshot and describe what you see in detail."
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
        print("📊 Request body size: \(jsonData.count) bytes")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("🌐 Response Status: \(httpResponse.statusCode)")
        }
        
        // Log raw response
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
        print("❌ API call failed: \(error)")
    }
}

// COMMENTED OUT: Original Ollama implementation
/*
func testOllamaAPI() async {
    let imagePath = "./img.png"
    
    print("🔍 Loading image from: \(imagePath)")
    
    guard let base64Image = convertImageToBase64(imagePath: imagePath) else {
        print("❌ Failed to process image")
        return
    }
    
    print("✅ Image loaded successfully")
    print("📦 Base64 length: \(base64Image.count) characters")
    print("📦 Base64 preview: \(String(base64Image.prefix(100)))...")
    
    let url = URL(string: "http://localhost:11434/api/generate")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let payload: [String: Any] = [
        "model": "llava",
        "prompt": "Analyze this screenshot and describe what you see in detail.",
        "images": [base64Image],
        "stream": false
    ]
    
    do {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData
        
        print("🚀 Sending request to Ollama...")
        print("📊 Request body size: \(jsonData.count) bytes")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("🌐 Response Status: \(httpResponse.statusCode)")
        }
        
        // Log raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 Raw response length: \(data.count) bytes")
            print("📥 Raw response: \(responseString)")
        }
        
        if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("✅ Successfully parsed JSON response")
            
            if let responseText = jsonResponse["response"] as? String {
                print("🤖 LLM Response: \(responseText)")
                
                if responseText.isEmpty {
                    print("⚠️ LLM returned empty response")
                }
            } else {
                print("⚠️ No 'response' field in JSON")
                print("🔍 Available JSON keys: \(jsonResponse.keys)")
            }
            
            if let error = jsonResponse["error"] as? String {
                print("❌ Ollama error: \(error)")
            }
        } else {
            print("❌ Failed to parse response as JSON")
        }
        
    } catch {
        print("❌ API call failed: \(error)")
    }
}
*/

// Main execution
Task {
    await testOpenRouterAPI()
    exit(0)
}

RunLoop.main.run()