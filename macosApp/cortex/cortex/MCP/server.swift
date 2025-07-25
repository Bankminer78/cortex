import MCP

// Create a server with given capabilities
let server = Server(
    name: "CortexServer",
    version: "1.0.0",
    capabilities: .init(
        prompts: .init(listChanged: true),
        resources: .init(subscribe: true, listChanged: true),
        tools: .init(listChanged: true)
    )
)

// Create transport and start server
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
            description: "Perform calculations",
            // inputSchema: .object([
            //     "properties": .object([
            //         "expression": .string("Mathematical expression to evaluate")
            //     ])
            // ])
        )
    ]
    return .init(tools: tools)
}

// Register a tool call handler
server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    case "add_activity_rule":
        print("Adding activity rule with params: \(params.arguments ?? [:])")
        return .init(
            content: [.text("Activity rule added successfully")],
            isError: false
        )
        // let location = params.arguments?["location"]?.stringValue ?? "Unknown"
        // let units = params.arguments?["units"]?.stringValue ?? "metric"
        // let weatherData = getWeatherData(location: location, units: units) // Your implementation
        // return .init(
        //     content: [.text("Weather for \(location): \(weatherData.temperature)°, \(weatherData.conditions)")],
        //     isError: false
        // )

    case "enter_focus_mode":
        // if let expression = params.arguments?["expression"]?.stringValue {
        //     let result = evaluateExpression(expression) // Your implementation
        //     return .init(content: [.text("\(result)")], isError: false)
        // } else {
        //     return .init(content: [.text("Missing expression parameter")], isError: true)
        // }
        print("Entering focus mode")
        return .init(
            content: [.text("Focus mode activated")],
            isError: false
        )

    default:
        return .init(content: [.text("Unknown tool")], isError: true)
    }
}

// -------------------------------------------------
// Need to implement the logic for the tools here




// Register a resource list handler
server.withMethodHandler(ListResources.self) { params in
    let resources = [
        // Resource(
        //     uri: "resource://knowledge-base/articles",
        //     name: "Knowledge Base Articles",
        //     description: "Collection of support articles and documentation"
        // ),
        // Resource(
        //     uri: "resource://system/status",
        //     name: "System Status",
        //     description: "Current system operational status"
        // )
    ]
    return .init(resources: resources, nextCursor: nil)
}
