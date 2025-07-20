import MCP
import Foundation

struct Rule: Codable {
    let appOrSite: String
    let block: Bool
}

class ActivityTrackerMCPServer {
    private var rules: [Rule] = []
    private var focusModeActive = false

    // Define the MCP "tool"
    let setRulesTool = Tool(
        name: "set_activity_rules",
        inputSchema: [
            "rules": [ ["appOrSite": "String", "block": "Bool"] ]
        ]
    )

    // Implement the handler for MCP's tool call
    func withMethodHandler(_ method: CallTool.Type) -> Result {
        switch method.tool {
        case "set_activity_rules":
            if let input = method.input as? [String: Any],
               let rules = input["rules"] as? [[String: Any]] {
                // Parse and apply
                self.rules = rules.map { Rule(appOrSite: $0["appOrSite"] as! String,
                                              block: $0["block"] as! Bool) }
                return .success(["status": "rules updated"])
            }
            return .error("invalid input")
        case "activate_focus_mode":
            self.focusModeActive = true
            return .success(["status": "focus mode activated"])
        default:
            return .error("unknown tool")
        }
    }
}
