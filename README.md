# Tech Spec: AI Accountability App (Physical Device)

## 1. Overview

This document outlines the technical specification for an AI-powered accountability application. The system uses a physical iOS device connected via USB to a macOS host. The iOS app periodically requests screenshots from the host, which are then analyzed on-device by a local LLM to determine if the user's activity aligns with their stated goals.

## 2. System Architecture

The architecture consists of three main components communicating over a local USB-proxied network connection:

- **iOS App** → **USB Cable (via iproxy)** → **macOS Flask Server** → **xcrun devicectl** → **Screenshot**

## 3. Components

### iOS Client Application

- **Description:** The user-facing application responsible for setting goals, triggering screenshot requests, and processing the results.
- **Language/Framework:** Swift, SwiftUI

**Key Responsibilities:**

- Maintain a Timer to trigger a request every N seconds.
- Use `URLSession` to send a GET request to `http://localhost:8000/screenshot`.
- Receive a JSON payload containing a Base64 encoded image.
- Decode the image and perform on-device OCR (Vision) and LLM analysis.
- **Configuration:** Requires `NSAllowsLocalNetworking` set to `true` in `Info.plist`.

### macOS Backend Server

- **Description:** A lightweight web server that listens for requests from the iOS app and orchestrates the screenshot process on the host machine.
- **Language/Framework:** Python 3, Flask

**Key Responsibilities:**

- Expose a single endpoint: `GET /screenshot`.
- Execute the `xcrun devicectl diagnostics screenshot` shell command to capture the screen of the connected device.
- Read the resulting image file from disk.
- Encode the image to Base64 and return it in a JSON response.
- Clean up the temporary image file.

### USB Proxy Service

- **Description:** A command-line utility that forwards network traffic from the iOS device to the macOS host over the USB cable. This allows the app to use localhost to reach the server.
- **Technology:** iproxy (from the tidevice Python package)
- **Command:** `iproxy 8000 8000`

## 4. Data Flow

1. The iOS app's Timer fires.
2. The app sends a GET request to `http://localhost:8000/screenshot`.
3. The iproxy service forwards this request over USB to the Flask server on the Mac.
4. The Flask server executes `xcrun devicectl` to save a screenshot of the iPhone's screen to the Mac's disk.
5. The server reads the image file, encodes it to Base64, and places it in a JSON object: `{"status": "success", "image": "<base64_string>"}`
6. The server sends the JSON response back through the proxy to the app.
7. The app decodes the Base64 string into a UIImage for on-device processing.

## 5. Setup & Execution

- **Terminal 1:** Run the backend server: `python server.py`
- **Terminal 2:** Run the USB proxy: `iproxy 8000 8000`
- **Xcode:** Run the app on the connected physical device.

## 6. Risks & Mitigations

- **Performance:** The `xcrun devicectl` command can be slow.
  - _Mitigation:_ Increase the timer interval for the demo (e.g., 15-20 seconds) to ensure the previous request completes.
- **Device State:** Screenshot command may fail if the device is locked.
  - _Mitigation:_ Ensure the device remains unlocked during the demo. The server should handle this error gracefully.
