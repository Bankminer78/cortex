import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var bridge: MCPBridge?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        bridge = MCPBridge()
        Task {
            do {
                try await bridge?.start()
            } catch {
                print("Failed to start MCPBridge: \(error)")
            }
        }
    }
}
