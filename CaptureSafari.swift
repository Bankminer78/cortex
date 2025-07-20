// CaptureSafari.swift
// Polls every 3 s; if the front-most app is Safari, saves a PNG of its key window
// to ~/Desktop/SafariCapture_<timestamp>.png

import Cocoa
import CoreGraphics
import ScreenCaptureKit

// MARK: – Helpers

func frontmostApp() -> NSRunningApplication? {
    return NSWorkspace.shared.frontmostApplication
}

func foremostWindowID(for pid: pid_t) -> CGWindowID? {
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
        return windowID          // first match is the front-most
    }
    return nil
}

func captureWindow(id: CGWindowID) async -> CGImage? {
    do {
        // Get available content
        let content = try await SCShareableContent.current
        
        // Find the window with matching ID
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            print("⚠️ Window not found")
            return nil
        }
        
        // Create configuration for window capture
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.capturesAudio = false
        
        // Create filter for specific window
        let filter = SCContentFilter(desktopIndependentWindow: window)
        
        // Capture the window
        let screenshot = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        return screenshot
    } catch {
        print("⚠️ Capture error: \(error)")
        return nil
    }
}

func savePNG(_ img: CGImage, suffix: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let ts = formatter.string(from: Date())
    let url = URL(fileURLWithPath: "\(NSHomeDirectory())/Desktop/SafariCapture_\(ts)\(suffix).png")
    try? data.write(to: url)
    print("💾 Saved \(url.lastPathComponent)")
}

// MARK: – Poll loop

func performCapture() {
    Task {
        guard let app = frontmostApp(),
              app.bundleIdentifier == "com.apple.Safari" else { return }

        guard let winID = foremostWindowID(for: app.processIdentifier),
              let img = await captureWindow(id: winID) else {
            print("⚠️  Could not capture window (permission?)")
            return
        }
        savePNG(img, suffix: "")
    }
}

let timer = Timer(timeInterval: 3.0, repeats: true) { _ in
    performCapture()
}

RunLoop.main.add(timer, forMode: .common)
print("⌛️  Watching for Safari every 3 s…  (Ctrl-C to quit)")
RunLoop.main.run()