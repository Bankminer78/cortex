# macOS/Windows Accountability App - Technical Specification

## Project Overview

A cross-platform accountability application that monitors user activity across applications and websites, using semantic rule-based checking with local LLM processing to prevent distractions while allowing legitimate work.

## Technology Stack

- **Framework**: Tauri 2.0
- **Frontend**: React 18 + TypeScript + Tailwind CSS
- **Backend**: Rust (latest stable)
- **Database**: SQLite with SQLx
- **LLM Runtime**: candle-core (local inference)
- **Build System**: Cargo + npm

## Project Structure

```
accountability-app/
├── src-tauri/
│   ├── src/
│   │   ├── main.rs                 // App entry point and Tauri setup
│   │   ├── lib.rs                  // Module declarations
│   │   ├── commands/               // Tauri command handlers
│   │   │   ├── monitoring.rs       // Start/stop monitoring commands
│   │   │   ├── rule_management.rs  // Natural language rule creation/editing
│   │   │   └── ai_processing.rs    // Dual AI model management
│   │   ├── services/               // Core business logic
│   │   │   ├── system_monitor.rs   // Cross-platform activity monitoring
│   │   │   ├── rule_engine.rs      // Rule evaluation and violation detection
│   │   │   ├── ai_service.rs       // Dual LLM integration (rule generation + monitoring)
│   │   │   ├── nlp_service.rs      // Natural language rule parsing
│   │   │   └── database.rs         // SQLite operations
│   │   ├── models/                 // Data structures
│   │   │   ├── rule.rs            // Rule definitions and validation
│   │   │   ├── activity.rs        // Activity logging structures
│   │   │   └── violation.rs       // Violation records
│   │   ├── utils/                  // Shared utilities
│   │   │   ├── logger.rs          // Structured logging setup
│   │   │   └── config.rs          // Configuration management
│   │   └── platform/              // OS-specific implementations
│   │       ├── macos.rs           // macOS accessibility APIs
│   │       └── windows.rs         // Windows UI Automation
├── src/                           // React frontend
│   ├── components/                // UI components
│   │   ├── Dashboard.tsx          // Monitoring status and recent activity
│   │   ├── RuleChat.tsx           // Conversational rule creation interface
│   │   ├── RuleList.tsx           // Display and manage existing rules
│   │   ├── ActivityLog.tsx        // Historical activity and violations
│   │   └── Settings.tsx           // App configuration
│   ├── services/                  // API layer and types
│   └── hooks/                     // React hooks for state management
├── browser-extension/             // Cross-browser extension
└── migrations/                    // SQLite schema migrations
```

## Core Architecture Strategy

### 1. Modular Service Architecture

**System Monitor Service**
- **Purpose**: Cross-platform activity monitoring with minimal performance impact
- **Strategy**: Use OS-specific accessibility APIs to extract structured data rather than pixel analysis
- **Edge Cases**: 
  - Handle sandboxed applications with limited accessibility access
  - Graceful degradation when accessibility permissions are denied
  - Rate limiting to prevent CPU overload during rapid window switching
  - Handle applications that block accessibility APIs (some games, security software)

**Rule Engine Service**
- **Purpose**: Lightweight, fast rule evaluation with semantic understanding
- **Strategy**: Two-tier evaluation: fast pattern matching first, then AI semantic analysis only when needed
- **Edge Cases**:
  - Handle ambiguous contexts where basic patterns fail
  - Manage false positives from AI misinterpretation
  - Handle rapid context switching (user switches between allowed and blocked content quickly)
  - Deal with partial UI data when accessibility APIs return incomplete information

**AI Service Enhancement for Rule Generation**
- **Purpose**: Convert natural language to structured rules and provide real-time rule evaluation
- **Strategy**: Dual-model approach - one specialized for rule generation, one optimized for activity monitoring
- **Rule Generation Model**: Larger model (7B-13B parameters) with strong instruction following for complex rule parsing
- **Monitoring Model**: Smaller, faster model (1B-3B parameters) optimized for binary classification

**Enhanced Edge Cases**:
- **Ambiguous Language**: Handle vague requests like "don't let me waste time" by asking clarifying questions
- **Conflicting Instructions**: Detect and resolve contradictions in natural language input
- **Complex Temporal Logic**: Parse sophisticated time-based rules ("only during work hours except lunch break")
- **Context Switching**: Handle rules that depend on previous activities or stated intentions
- **Rule Refinement**: Allow iterative improvement through natural language feedback

### 2. Data Collection Strategy

**Structured Data Extraction**
- **Primary Method**: Extract semantic meaning from UI elements (text, URLs, window titles, form inputs)
- **Fallback Method**: Screenshots only when structured data is insufficient
- **Strategy**: Build lightweight "UI fingerprints" that capture intent without storing sensitive content

**Privacy-First Approach**
- Never log sensitive content (passwords, personal messages, financial data)
- Process data in memory, log only metadata and violation summaries
- Allow users to mark applications as "private" to exclude from monitoring

**Performance Optimization**
- Use lazy evaluation: only run AI processing when basic patterns suggest potential violation
- Cache common evaluations to avoid repeated AI inference
- Batch process activities during idle periods

### 3. Rule System Design

**Flexible Rule Definition**
- **App-Level Rules**: Define behavior expectations per application
- **Context-Aware Rules**: Same app, different rules based on stated user intent
- **Time-Based Rules**: Different rules for work hours vs. personal time
- **Cascading Rules**: Global rules with app-specific overrides

**Rule Evaluation Hierarchy**
1. **Whitelist Check**: Explicitly allowed activities (highest priority)
2. **Pattern Matching**: Fast regex/glob pattern evaluation
3. **Semantic Analysis**: AI-powered intent evaluation (slowest, highest accuracy)
4. **Blacklist Check**: Explicitly blocked activities

**Edge Case Handling**
- **Conflicting Rules**: Clear precedence system (specific > general, newer > older)
- **Partial Matches**: Handle cases where activity partially matches multiple rules
- **Context Switching**: Maintain activity history to understand user intent transitions
- **False Positives**: Learn from user corrections to improve rule accuracy

### 4. Cross-Platform Implementation

**macOS Strategy**
- Use Accessibility API for UI element extraction
- NSWorkspace for application monitoring
- Carbon Events for global keyboard/mouse tracking
- Handle System Integrity Protection limitations

**Windows Strategy**
- UI Automation API for accessibility data
- Windows Management API for application tracking
- Low-level hooks for input monitoring
- Handle UAC restrictions and permission requirements

**Browser Extension Strategy**
- Single codebase for Chrome/Edge using Manifest V3
- Native messaging for secure communication with main app
- Content scripts for page-level data extraction
- Handle cross-origin restrictions and CSP limitations

### 5. Performance and Scalability

**Resource Management**
- Monitor CPU usage and throttle monitoring frequency if needed
- Use efficient data structures for rule storage and lookup
- Implement connection pooling for database operations
- Memory management for AI model loading/unloading

**Scalability Considerations**
- Design for handling hundreds of rules efficiently
- Support for multiple user profiles on same machine
- Efficient storage and retrieval of historical activity data
- Background processing to avoid UI blocking

### 6. Error Handling and Resilience

**System Monitoring Failures**
- Graceful degradation when accessibility APIs fail
- Retry mechanisms for transient system errors
- User notification when monitoring capabilities are limited
- Fallback to browser-only monitoring if system monitoring fails

**AI Service Failures**
- Fallback to pattern-based rules when AI is unavailable
- Handle model corruption or loading failures
- Queue activities for later processing during AI service downtime
- User notification when semantic evaluation is unavailable

**Database and Storage Issues**
- Transaction rollback for failed operations
- Database repair and recovery mechanisms
- Backup and restore functionality for rule configurations
- Handle disk space limitations gracefully

### 7. Natural Language Rule Creation

**Core Strategy**
- Users describe rules in plain English: "Let me use Instagram to message friends but block me from scrolling the feed"
- LLM converts natural language to structured JSON rule format
- No complex UI forms or technical configuration required
- Immediate rule testing and refinement through conversation

**Rule Generation Pipeline**
1. **Natural Language Input**: User describes desired behavior in conversational terms
2. **Context Extraction**: LLM identifies key components (apps, allowed actions, blocked actions, intent)
3. **JSON Generation**: Convert to structured rule format with proper patterns and semantic checks
4. **Validation**: Check rule logic and potential conflicts with existing rules
5. **User Confirmation**: Show generated rule in human-readable format for approval
6. **Database Storage**: Save validated rule to local database

**Rule JSON Schema**
```json
{
  "id": "uuid",
  "name": "user-friendly rule name",
  "description": "natural language description",
  "app_patterns": ["regex patterns for matching applications"],
  "url_patterns": ["regex patterns for URLs (optional)"],
  "intent_context": "what the user is trying to accomplish",
  "allowed_actions": [
    "specific allowed behaviors",
    "navigation patterns",
    "interaction types"
  ],
  "blocked_actions": [
    "specific blocked behaviors", 
    "time limits",
    "content restrictions"
  ],
  "semantic_checks": [
    "questions for AI to evaluate user behavior",
    "context-aware validation rules"
  ],
  "triggers": {
    "time_based": "optional time restrictions",
    "usage_limits": "optional usage duration limits",
    "context_switches": "rules for when context changes"
  },
  "responses": {
    "warning_message": "custom message for violations",
    "action_type": "warn|block|redirect",
    "grace_period": "seconds before enforcement"
  }
}
```

**Natural Language Processing Strategy**
- **Intent Recognition**: Identify the user's productivity goal vs. distraction patterns
- **App/Service Mapping**: Convert common names to technical identifiers ("Instagram" → app patterns)
- **Action Classification**: Distinguish between productive actions (messaging) vs. consumptive actions (scrolling)
- **Temporal Understanding**: Parse time-based constraints ("during work hours", "for more than 10 minutes")
- **Context Awareness**: Understand related activities and edge cases

**Example Conversions**


*Input*: "Block me from Instagram feed but let me message my friends and check my business account"
*Generated Rule*:
```json
{
  "name": "Instagram Communication Only",
  "intent_context": "social communication and business management",
  "app_patterns": ["Instagram", ".*instagram\\.com.*"],
  "allowed_actions": [
    "navigate to direct messages",
    "send and receive messages",
    "access business account dashboard",
    "post business content",
    "respond to comments on business posts"
  ],
  "blocked_actions": [
    "scroll main feed",
    "browse explore page",
    "watch stories from non-business accounts",
    "browse reels"
  ],
  "semantic_checks": [
    "Is the user actively communicating with specific people?",
    "Are they managing their business account?",
    "Are they consuming content vs. creating/communicating?"
  ]
}
```

**Advanced Rule Features**
- **Contextual Rules**: Same app, different rules based on time of day or stated intent
- **Learning Rules**: Rules that adapt based on user corrections and usage patterns
- **Compound Rules**: Multiple conditions that must be met together
- **Exception Handling**: Temporary overrides for specific situations

**User Experience Considerations**

**Non-Intrusive Monitoring**
- Minimal visual indicators when monitoring is active
- Configurable notification levels (silent, gentle warnings, blocking)
- Quick pause/resume functionality for legitimate exceptions
- Emergency override mechanism for urgent situations

**Conversational Rule Management**
- Chat-like interface for creating and modifying rules
- Natural language rule editing: "Make that Instagram rule less strict"
- Rule explanation in plain English when violations occur
- Quick rule adjustment through conversation

**Violation Handling**
- Graduated responses: warning → gentle redirect → blocking
- User feedback mechanism to improve rule accuracy
- Context-aware messaging explaining why activity was flagged
- Quick correction mechanism for false positives

### 8. Security and Privacy

**Local Processing**
- All AI inference happens locally, no cloud dependencies
- Encrypted storage for sensitive configuration data
- No telemetry or usage data transmission
- User control over all data retention policies

**Permission Management**
- Clear explanation of required system permissions
- Graceful degradation when permissions are limited
- User control over monitoring scope and exclusions
- Audit log of all data access and processing

### 9. Development and Testing Strategy

**Modular Development**
- Independent service modules for easier testing
- Mock interfaces for cross-platform development
- Feature flags for gradual rollout of functionality
- Comprehensive unit tests for rule evaluation logic

**Testing Approach**
- Automated testing with simulated UI interactions
- Cross-platform testing on both macOS and Windows
- Performance testing with various rule configurations
- User acceptance testing with real-world distraction scenarios

### 10. Future Extensibility

**Plugin Architecture**
- Support for custom rule types and evaluation logic
- Integration points for external accountability systems
- API for third-party application integration
- Extensible UI components for custom rule interfaces

**Advanced Features (Future)**
- Machine learning for personalized rule optimization
- Team/family accountability features
- Integration with productivity tools and calendars
- Advanced analytics and reporting capabilities