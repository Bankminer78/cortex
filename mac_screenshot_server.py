#!/usr/bin/env python3
"""
Mac Screenshot Server
Runs a local HTTP server that takes screenshots via Xcode Simulator and serves them to the iOS app
"""

# import requests  # No longer needed for WDA
import base64
import datetime
import pathlib
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import threading
import time

# WDA_URL = "http://127.0.0.1:8100/screenshot"  # No longer used
SERVER_PORT = 8090

class ScreenshotHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/screenshot':
            self.handle_screenshot_request()
        elif self.path == '/health':
            self.handle_health_check()
        elif self.path == '/hello':
            self.handle_hello_request()
        else:
            self.send_error(404, "Not Found")
    
    def handle_screenshot_request(self):
        try:
            # Use Xcode Simulator screenshot command instead of WDA
            print(f"📡 Taking screenshot using Xcode Simulator...")
            
            # Create temporary file for screenshot
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            temp_filename = f"/tmp/simulator_screenshot_{timestamp}.png"
            
            # Execute xcrun simctl io booted screenshot command
            import subprocess
            result = subprocess.run([
                "xcrun", "simctl", "io", "booted", "screenshot", temp_filename
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                raise RuntimeError(f"Simulator screenshot failed: {result.stderr}")
            
            # Read the screenshot file and convert to base64
            with open(temp_filename, "rb") as f:
                image_bytes = f.read()
            
            b64_image = base64.b64encode(image_bytes).decode('utf-8')
            
            # Clean up temp file
            import os
            try:
                os.remove(temp_filename)
            except:
                pass
            
            # Send response to iOS app
            response_data = {
                "success": True,
                "image": b64_image,
                "timestamp": datetime.datetime.now().isoformat()
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(response_data).encode())
            
            print(f"✅ Simulator screenshot served successfully ({len(image_bytes)} bytes)")
            
        except Exception as e:
            print(f"❌ Error taking screenshot: {e}")
            error_response = {
                "success": False,
                "error": str(e)
            }
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(error_response).encode())
    
    def handle_health_check(self):
        response_data = {"status": "healthy", "server": "mac_screenshot_server"}
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(response_data).encode())

    def handle_hello_request(self):
        print("Hello from Mac!")
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps({"message": "Hello from Mac!"}).encode())
    
    def log_message(self, format, *args):
        # Override to reduce verbose logging
        print(f"[{datetime.datetime.now().strftime('%H:%M:%S')}] {format % args}")

def main():
    server_address = ('', SERVER_PORT)
    httpd = HTTPServer(server_address, ScreenshotHandler)
    
    print(f"🚀 Mac Screenshot Server starting on port {SERVER_PORT}")
    print(f"📱 iOS Simulator app should connect to: http://localhost:{SERVER_PORT}")
    print(f"📲 Using Xcode Simulator screenshot: xcrun simctl io booted screenshot")
    print("Press Ctrl+C to stop")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped")
        httpd.server_close()

if __name__ == "__main__":
    main()