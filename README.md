# Cortex: AI-Powered Productivity Monitoring

## Overview

Cortex is an AI-powered accountability application that monitors user activity and enforces productivity goals. The system captures screenshots, analyzes them using LLMs, and triggers interventions based on user-defined rules.

## Current Status

**✅ Baseline Implementation Complete:**
- Loop every 2s to capture foreground window → PNG
- Store {timestamp, bundleId, activity_label} in SQLite database
- Hard-coded rule: "If Instagram scrolling ≥ 10s → show popup"
- OpenAI/OpenRouter integration for activity classification
- Safari window capture with ScreenCaptureKit

## Architecture

The current system consists of:
- **macOS App** (Swift/SwiftUI) - Main monitoring application
- **Background Service** - Screenshot capture and LLM analysis
- **SQLite Database** - Activity logging and rule storage
- **LLM Integration** - OpenAI/OpenRouter for image classification

## TODO: Development Roadmap

### Phase 1: Code Organization & Modularity 🏗️
- [ ] **Refactor into modular components**
  - [ ] Extract `LLMClient` module (OpenAI/OpenRouter/Local model switching)
  - [ ] Extract `DatabaseManager` module (SQLite operations, migrations)
  - [ ] Extract `ScreenCaptureManager` module (ScreenCaptureKit operations)
  - [ ] Extract `RuleEngine` module (rule evaluation and triggers)
  - [ ] Extract `ActionDispatcher` module (popups, notifications, blocking)
  - [ ] Create `CortexSDK` framework for external integration

### Phase 2: Natural Language Rule Compiler 🤖
- [ ] **Design rule compilation system**
  - [ ] Create `RuleCompiler` module
  - [ ] Design rule JSON schema (time windows, count triggers, AND/OR logic)
  - [ ] Implement OpenAI integration for NL → JSON conversion
  - [ ] Add rule validation and error handling
  - [ ] Create rules database table
- [ ] **Example transformations:**
  - [ ] "Don't let me watch YouTube Shorts for more than 5 minutes per hour" → Time window rule
  - [ ] "Block Instagram after 30 scrolls" → Count-based rule
  - [ ] "No social media during work hours (9-5)" → Time-based rule

### Phase 3: Multi-App Monitoring 📱
- [ ] **Extend activity monitoring**
  - [ ] Monitor ALL foreground apps (not just Safari)
  - [ ] Extract bundle IDs and app names
  - [ ] Store app metadata in database
  - [ ] Add domain detection for web browsers
  - [ ] Implement lazy LLM classification (label initially NULL)

### Phase 4: Advanced Rule Engine ⚙️
- [ ] **Implement flexible rule evaluation**
  - [ ] Time window evaluator (`≥ N seconds in M seconds`)
  - [ ] Count-based triggers (`scrolls > 30`)
  - [ ] Boolean logic support (AND/OR combinations)
  - [ ] Rule priority and conflict resolution
  - [ ] Real-time rule evaluation after each DB insert
- [ ] **Rule management UI**
  - [ ] Add/edit/delete rules interface
  - [ ] Rule testing and preview
  - [ ] Rule performance monitoring

### Phase 5: Screen Time Integration 🔒
- [ ] **macOS Screen Time SDK integration**
  - [ ] Add `ManagedSettingsStore` for app blocking
  - [ ] Implement shield overlays for blocked apps
  - [ ] Add local notification system
  - [ ] Create `ActionDispatcher.lock(bundleId)` API
  - [ ] Create `ActionDispatcher.notify(text)` API

### Phase 6: External Action System 🌐
- [ ] **Smithery integration**
  - [ ] Design webhook system: `POST /smithery`
  - [ ] Send context: `{goal, violation, screenshot}`
  - [ ] Parse action responses: `send_email`, `post_tweet`, etc.
  - [ ] Implement Mail API integration
  - [ ] Implement AppleScript automation
  - [ ] Add custom action plugin system

### Phase 7: Local Model Integration 🏠
- [ ] **Replace cloud models with local inference**
  - [ ] Integrate Ollama for local model management
  - [ ] Pull CogVLM-7B or LLaVA-Next-10B models
  - [ ] Implement local LLM client (`localhost:11434`)
  - [ ] Add cloud fallback (OpenRouter) when local unavailable
  - [ ] Performance optimization for local inference

### Phase 8: Developer SDK 🛠️
- [ ] **Package CortexSDK for external use**
  - [ ] Create Swift Package Manager structure
  - [ ] Expose `func addGoal(text: String)` - auto NL compilation
  - [ ] Expose `func observeViolations(handler: (Violation) -> Void)`
  - [ ] Add comprehensive documentation and examples
  - [ ] Create sample integration apps
  - [ ] Publish to Swift Package Index

### Phase 9: Testing & Polish ✨
- [ ] **Comprehensive testing suite**
  - [ ] Unit tests for all modules
  - [ ] Integration tests for rule engine
  - [ ] UI automation tests
  - [ ] Performance benchmarking
  - [ ] Memory leak detection
- [ ] **User experience improvements**
  - [ ] Onboarding flow
  - [ ] Settings and preferences
  - [ ] Activity dashboard and analytics
  - [ ] Export/import configuration

### Phase 10: Distribution 🚀
- [ ] **Prepare for release**
  - [ ] App Store preparation (if applicable)
  - [ ] Code signing and notarization
  - [ ] User documentation
  - [ ] Privacy policy and compliance
  - [ ] Beta testing program

## Quick Start

```bash
# Current setup (baseline)
cd macosApp/cortex
open cortex.xcodeproj
# Build and run in Xcode
```

## Architecture Notes

The system is designed with modularity in mind. Each phase builds upon the previous one while maintaining clean separation of concerns. The ultimate goal is a plugin-based architecture where rules, actions, and monitoring can be extended by third-party developers.
