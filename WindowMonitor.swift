// WindowMonitor.swift
// Modular window monitoring and LLM analysis for macOS

import Cocoa
import CoreGraphics
import ScreenCaptureKit
import Foundation

class WindowMonitor {
    
    // MARK: - Window Detection
    
    static func getFrontmostApp() -> NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }
    
    static func isSafariInFocus() -> Bool {
        guard let app = getFrontmostApp(),
              let bundleId = app.bundleIdentifier else { return false }
        return bundleId == "com.apple.Safari"
    }
    
    static func getForegroundWindowID(for pid: pid_t) -> CGWindowID? {
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
            return windowID
        }
        return nil
    }
    
    // MARK: - Screenshot Capture
    
    static func captureWindow(id: CGWindowID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.current
            
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                print("⚠️ Window not found for ID: \(id)")
                return nil
            }
            
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
            print("⚠️ Screenshot capture error: \(error)")
            return nil
        }
    }
    
    // MARK: - LLM Integration
    
    static func sendToLLM(image: CGImage) async {
        // Convert CGImage to base64
        guard let base64Image = convertImageToBase64(image) else {
            print("⚠️ Failed to convert image to base64")
            return
        }
        
        await callOllamaAPI(base64Image: base64Image)
    }
    
    private static func convertImageToBase64(_ image: CGImage) -> String? {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return data.base64EncodedString()
    }
    
    private static func callOllamaAPI(base64Image: String) async {
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": "llama3",
            "prompt": "Analyze this screenshot and describe what the user is doing. Focus on productivity and goal alignment.",
            "images": [base64Image],
            "stream": false
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 LLM API Response Status: \(httpResponse.statusCode)")
            }
            
            if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseText = jsonResponse["response"] as? String {
                print("🤖 LLM Response: \(responseText)")
            } else {
                print("⚠️ Failed to parse LLM response")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Raw response: \(responseString)")
                }
            }
            
        } catch {
            print("⚠️ LLM API call failed: \(error)")
        }
    }
    
    // MARK: - Main Monitor Function
    
    static func checkAndProcessFocusedWindow() async {
        guard isSafariInFocus() else {
            print("🔍 Safari not in focus, skipping...")
            return
        }
        
        print("🎯 Safari detected in focus - capturing screenshot...")
        
        guard let app = getFrontmostApp(),
              let windowID = getForegroundWindowID(for: app.processIdentifier) else {
            print("⚠️ Could not get window ID for Safari")
            return
        }
        
        guard let screenshot = await captureWindow(id: windowID) else {
            print("⚠️ Failed to capture Safari window")
            return
        }
        
        print("📸 Screenshot captured, sending to LLM...")
        await sendToLLM(image: screenshot)
    }
}