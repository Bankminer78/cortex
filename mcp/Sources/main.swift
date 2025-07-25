// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import MCP
import CortexSDK
 
let server = Server(
    name: "Cortex MCP Server",
    version: "1.0.0",
    capabilities: .init(tools: .init(listChanged: false))
)
 
let transport = StdioTransport()
try await server.start(transport: transport)


// Register a tool list handler
server.withMethodHandler(ListTools.self) { _ in
    let tools = [
        Tool(
            name: "add_activity_rule",
            description: "Add a rule to restrict access to certain uses of certain apps",
            inputSchema: .object([
                "properties": .object([
                    "rule": .string("Description of a rule to restrict access to a certain app or certain uses of an app. Eg. 'Block videos of football on YouTube'"),
                ])
            ])
        ),
        Tool(
            name: "enter_focus_mode",
            description: "Enter focus mode blocking all distractions like social media and games or other apps as specified by the user optionally",
            inputSchema: .object([
                "properties": .object([
                    "apps": .array("List of apps to block during focus mode", items: .string("App name")),
                ])
            ])
        )
    ]
    return .init(tools: tools)
}

// Register a tool call handler
server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    case "add_activity_rule":
    var activityAdded = false
        if let rule = params.arguments?["rule"]?.stringValue {
            print("Adding activity rule: \(rule)")
            CortexSDK.addActivityRule(rule: rule)
            activityAdded = true
        } else {
            print("No rule provided for adding activity rule")
        }
        if !activityAdded {
            return .init(
                content: [.text("No activity rule added")],
                isError: true
            )
        }
        print("Adding activity rule with params: \(params.arguments ?? [:])")

        return .init(
            content: [.text("Activity rule added successfully")],
            isError: false
        )

    case "enter_focus_mode":
    
    var focusModeActive = false
        if let apps = params.arguments?["apps"]?.arrayValue {
            print("Entering focus mode with apps: \(apps)")
            CortexSDK.activateFocusMode(apps: apps.map { $0.stringValue })
            focusModeActive = true
        } else if focusModeActive {
            print("Entering focus mode with no specific apps")
            CortexSDK.activateFocusMode(apps: [])
            focusModeActive = true
        } else {
            print("Entering focus mode without specific apps")
        }
        print("Entering focus mode")
        if !focusModeActive {
            return .init(
                content: [.text("Focus mode is already active")],
                isError: true
            )
        }
        return .init(
            content: [.text("Focus mode activated")],
            isError: false
        )

    default:
        return .init(content: [.text("Unknown tool")], isError: true)
    }
}

await server.waitUntilCompleted()