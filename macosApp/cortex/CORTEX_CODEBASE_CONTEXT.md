# Cortex Productivity Monitor - Codebase Context

## 🎯 Project Overview

**Cortex** is an AI-powered macOS productivity monitoring application that uses computer vision and LLMs to detect unproductive activities and intervene with smart actions. The app captures screenshots of user activity, analyzes them with vision models, and triggers interventions like website blocking, app switching, and focused popups.

### Core Concept
- **Real-time monitoring**: Screenshots Safari windows every 3 seconds
- **LLM analysis**: Uses OpenAI/OpenRouter APIs to classify user activities
- **Smart interventions**: Blocks distracting websites, switches to productive apps, shows focused popups
- **Rule-based system**: Configurable time windows and triggers for different intervention types

## 🏗️ Architecture Overview

The codebase follows a **modular architecture** with clean separation of concerns:

```
Core/
├── LLMClient.swift           # AI model integration (OpenAI/OpenRouter)
├── DatabaseManager.swift    # SQLite activity logging & rules storage
├── ScreenCaptureManager.swift # macOS ScreenCaptureKit integration
├── RuleEngine.swift         # Rule evaluation & violation detection
├── ActionDispatcher.swift   # Intervention actions & MCP interface
└── CortexSDK.swift          # High-level public API

Service/
└── BackgroundService.swift  # Main orchestrator & monitoring loop
```

### Current Capabilities
✅ **Safari-only monitoring** (only triggers LLM analysis when Safari is in focus)  
✅ **Activity classification** (shopping, scrolling, productive work, etc.)  
✅ **Database logging** with SQLite migrations  
✅ **Smart interventions** including Screen Time blocking, browser navigation, app switching  
✅ **MCP-compatible interface** for LLM tool calling  
✅ **Rule engine** with time windows, count limits, and scheduling  

## 📁 File Structure & Components

### Core Modules

#### **LLMClient.swift** - AI Integration
```swift
// Supports multiple providers
enum LLMProvider { case openAI, openRouter, local }

// Main interface
protocol LLMClientProtocol {
    func analyze(image: CGImage, prompt: String) async throws -> LLMResponse
    func configure(provider: LLMProvider, apiKey: String?)
}
```
- **Purpose**: Abstracts LLM providers for vision analysis
- **Current providers**: OpenAI GPT-4V, OpenRouter
- **Key features**: Provider switching, error handling, response parsing

#### **DatabaseManager.swift** - Data Persistence
```swift
// Activity logging
struct ActivityRecord {
    let timestamp: Double
    let activity: String      // "shopping", "scrolling", "productive"
    let productive: Bool
    let app: String
    let bundleId: String?
    let domain: String?       // for browser activities
}

// Rule storage
struct Rule {
    let name: String
    let naturalLanguage: String
    let ruleJSON: String
    let isActive: Bool
}
```
- **Database**: SQLite with automatic migrations
- **Tables**: `activity_log`, `rules`
- **Features**: Connection recovery, column addition migrations, prepared statements

#### **ScreenCaptureManager.swift** - System Integration
```swift
protocol ScreenCaptureManagerProtocol {
    func captureSafariWindow() async throws -> CaptureResult?
    func captureWindow(bundleId: String) async throws -> CaptureResult?
    func getForegroundApp() -> AppInfo?
    func extractDomain(from windowTitle: String?) -> String?
}
```
- **Framework**: ScreenCaptureKit (macOS 14.0+)
- **Capabilities**: Safari-specific capture, general window capture, domain extraction
- **Permissions**: Requires Screen Recording permission

#### **RuleEngine.swift** - Behavioral Logic
```swift
// Rule types supported
enum RuleType {
    case timeWindow    // "5 minutes of scrolling in 10 minutes"
    case count         // "more than 3 shopping sessions"
    case schedule      // "no social media during work hours"
    case combo         // combination of above
}

// Violation detection
struct RuleViolation {
    let rule: CompiledRule
    let triggerActivity: ActivityRecord
    let context: ViolationContext
    let timestamp: Date
}
```
- **Rule compilation**: Converts natural language to executable rules (future LLM integration)
- **Evaluation**: Time window analysis, count tracking, schedule enforcement
- **Context**: Tracks matching activities, durations, time windows

#### **ActionDispatcher.swift** - Intervention System
```swift
// Core intervention types
enum DispatchableAction {
    case popup(PopupConfig)
    case notification(NotificationConfig)
    case block(BlockConfig)
    case screenTimeShield(ScreenTimeShieldConfig)  // NEW
    case browserBack(BrowserBackConfig)            // NEW
    case appSwitch(AppSwitchConfig)               // NEW
}

// Smart intervention methods
func executeShoppingIntervention() async -> ActionResult
func executeSocialMediaIntervention() async -> ActionResult
func emergencyFocusMode() async -> ActionResult
```

**Key Features**:
- **Screen Time Shield**: Blocks websites using macOS Screen Time APIs
- **Browser Back**: Executes `window.history.back()` in Safari + shows popup
- **App Switch**: Opens productive apps (defaults to Notion)
- **MCP Interface**: `MCPActionDispatcher` with snake_case methods for LLM tool calling
- **Smart Interventions**: Combined actions (back + switch + shield)

#### **CortexSDK.swift** - Public API
```swift
@available(macOS 14.0, *)
public class CortexSDK {
    public let llmClient: LLMClientProtocol
    public let databaseManager: DatabaseManagerProtocol
    public let screenCaptureManager: ScreenCaptureManagerProtocol
    public let ruleEngine: RuleEngineProtocol
    public var actionDispatcher: ActionDispatcherProtocol!
}
```
- **Purpose**: High-level API for external integration
- **Features**: Activity analysis, rule management, convenience methods
- **Global access**: `Cortex.shared` singleton

### Service Layer

#### **BackgroundService.swift** - Main Orchestrator
```swift
class BackgroundService {
    private let llmClient = LLMClient()
    private let databaseManager: DatabaseManager
    private let screenCaptureManager = ScreenCaptureManager()
    private let ruleEngine = RuleEngine()
    private var actionDispatcher: ActionDispatcher!
    
    // Main processing loop
    private func checkAndProcessFocusedWindow() async
    private func processWithLLM(captureResult: CaptureResult, appInfo: AppInfo) async
}
```

**Current Behavior**:
1. **Safari-only monitoring**: Only processes when Safari is in focus
2. **3-second intervals**: Captures and analyzes every 3 seconds
3. **Activity classification**: Uses LLM to determine user activity
4. **Rule evaluation**: Checks activities against configured rules
5. **Intervention dispatch**: Triggers appropriate actions for violations

## 🔄 Current Workflow

### Monitoring Flow
```
1. Timer triggers every 3 seconds
2. Get foreground app → Exit if not Safari
3. Capture Safari window screenshot
4. Send to LLM with activity classification prompt
5. Parse response (shopping/scrolling/productive/etc.)
6. Log activity to database
7. Evaluate against rules
8. Dispatch interventions for violations
9. Schedule next cycle
```

### Activity Classification Prompts
**Safari (Instagram detection)**:
```
Look at this screenshot and identify what the user is doing.

If this is Instagram, determine the specific activity:
- "messaging" if they are in Instagram DMs/messages talking to friends
- "scrolling" if they are browsing the feed, stories, or reels
- "posting" if they are creating/uploading content

If this is NOT Instagram, respond with:
- "not_instagram"

Respond with ONLY ONE WORD: messaging, scrolling, posting, not_instagram
```

**Other apps**:
```
Look at this screenshot and identify what the user is doing.

Respond with ONE WORD describing the activity:
- "productive" for work-related activities
- "browsing" for general browsing/reading
- "gaming" for games
- "social" for social media activities  
- "entertainment" for videos/movies
- "other" for anything else
```

## 🛠️ Technical Implementation Details

### Database Schema
```sql
-- Activity logging table
CREATE TABLE activity_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp REAL NOT NULL,
    activity TEXT NOT NULL,
    productive INTEGER NOT NULL,
    app TEXT NOT NULL,
    bundle_id TEXT,
    domain TEXT,
    created_at REAL DEFAULT (datetime('now'))
);

-- Rules storage table  
CREATE TABLE rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    natural_language TEXT NOT NULL,
    rule_json TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at REAL NOT NULL,
    updated_at REAL DEFAULT (datetime('now'))
);
```

### LLM Integration
- **OpenAI**: GPT-4V via `/v1/chat/completions` endpoint
- **OpenRouter**: Multiple model support via OpenRouter API
- **Error handling**: Automatic retries, fallback responses
- **Rate limiting**: Built-in request throttling

### macOS Integration
- **ScreenCaptureKit**: Modern screen capture framework
- **NSWorkspace**: App management and launching
- **AppleScript**: Safari automation and Screen Time control
- **UserNotifications**: System notifications

## 🎯 MCP Integration Ready

### MCPActionDispatcher Interface
```swift
@MainActor
public class MCPActionDispatcher {
    // LLM tool functions with snake_case naming
    public func shield_websites(domains: [String], duration: TimeInterval) async -> [String: Any]
    public func browser_back(message: String) async -> [String: Any]
    public func switch_to_app(app: String) async -> [String: Any]
    public func shopping_intervention() async -> [String: Any]
    public func social_media_intervention() async -> [String: Any]
    public func emergency_focus() async -> [String: Any]
}
```

**Usage Example**:
```swift
let mcpDispatcher = MCPActionDispatcher()

// Detect shopping activity and intervene
if activity.contains("cart") || activity.contains("checkout") {
    let result = await mcpDispatcher.shopping_intervention()
    // Returns: {"success": true, "tool": "shopping_intervention", "backNavigation": true, ...}
}
```

## 🚀 Extension Points & Future Development

### Ready for Enhancement

1. **Multi-App Support**: Currently Safari-only, easily extendable to other apps
2. **Rule Compilation**: Natural language → executable rules via LLM
3. **Advanced Interventions**: Website content blocking, productivity scoring
4. **Analytics Dashboard**: Usage patterns, productivity metrics
5. **Custom Actions**: Plugin system for user-defined interventions

### Key Integration Points

**BackgroundService Integration**:
```swift
// Easy activity-based intervention triggering
await actionDispatcher.handleActivityDetection(
    activity: "shopping",
    app: "Safari", 
    domain: "amazon.com"
)

// Direct intervention methods
await actionDispatcher.executeShoppingIntervention()
await actionDispatcher.emergencyFocusMode()
```

**Rule Engine Integration**:
```swift
// Add behavioral rules
let rule = CompiledRule(
    name: "Shopping Limit",
    type: .timeWindow,
    conditions: [
        RuleCondition(field: "activity", operator: .equal, value: .string("shopping"))
    ],
    timeWindow: TimeWindowConfig(durationSeconds: 300, lookbackSeconds: 600, threshold: 1),
    actions: [
        RuleAction(type: .popup, parameters: ["message": .string("Shopping break time!")])
    ]
)
try ruleEngine.addRule(rule)
```

## 🔧 Build & Development

### Requirements
- **macOS 14.0+**: Required for ScreenCaptureKit
- **Xcode 15+**: Swift 5.9+ with async/await
- **Permissions**: Screen Recording, Accessibility (for AppleScript)

### Build Commands
```bash
# Build (unsigned for development)
xcodebuild -scheme cortex build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# Run from Xcode or command line
open /Users/.../cortex.app
```

### Environment Setup
- Add OpenAI/OpenRouter API keys to environment variables
- Grant Screen Recording permission in System Preferences
- Ensure Accessibility permission for AppleScript automation

## 📝 Current State & Next Steps

### ✅ Completed
- Modular architecture with clean separation
- Safari-only monitoring with LLM analysis
- Database persistence with migrations
- Smart intervention system (shield/back/switch)
- MCP-compatible interface
- Rule engine foundation

### 🎯 Ready for Extension
- Multi-app monitoring (extend beyond Safari)
- Advanced rule compilation with LLM
- Real-time dashboard/analytics
- Custom intervention plugins
- Enhanced MCP tool integration

This codebase provides a solid foundation for AI-powered productivity monitoring with a clean, extensible architecture ready for advanced features and integrations.