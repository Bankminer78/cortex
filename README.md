# 🧠 Cortex: AI-Powered Productivity Monitoring

**Cortex** is a macOS application that helps users stay accountable to their productivity goals using AI. It captures and analyzes on-screen activity in real-time, intelligently enforcing custom rules and triggering interventions when focus strays.

---

## 🚀 Overview

Cortex combines screenshot capture, on-device logging, and AI-driven classification to monitor your screen activity and provide timely, context-aware nudges. Whether you're slipping into a scroll-hole or veering off task, Cortex helps you realign with your goals—automatically.

---

## ✅ Features

- ⏱️ **Real-Time Monitoring**: Captures the foreground window every 2 seconds
- 🧠 **LLM-Powered Analysis**: Classifies activity with OpenAI/OpenRouter
- 📃️ **Persistent Storage**: Stores `{timestamp, bundleId, activity_label}` in SQLite
- ⚠️ **Smart Rules**: Example rule — _"If Instagram scrolling ≥ 10s → show popup"_
- 🖥️ **macOS Native**: Built with SwiftUI and ScreenCaptureKit for secure, efficient monitoring

---

## 🤩 Architecture

**Cortex** is composed of the following modular components:

| Component                 | Description                                       |
| ------------------------- | ------------------------------------------------- |
| 🖥️ **macOS App**          | SwiftUI front-end for running the monitor         |
| 🧰 **Background Service** | Captures screenshots and classifies them          |
| 📂 **SQLite Database**    | Stores user activity and rules                    |
| 🧠 **LLM Integration**    | Uses OpenAI/OpenRouter to interpret user activity |
| 🔔 **Rule Engine**        | Evaluates productivity goals and triggers actions |

---

## 🎯 Example Use Case

> "I want to use Instagram to message people but always get sucked into the reels. Stop me from doomscrolling. Oh and I'm an impulsive shopper. Don't let me buy any more shoes"

Cortex detects this behavior through screenshots, identifies Instagram via bundle ID and image context, and triggers an alert when the rule is violated in real-time.

---

## 🔭 Availability

Cortex is built with modularity and extensibility in mind. Here are the different platforms where Cortex is available:

- 📱 **Android App**: A native app built with Kotlin, designed for seamless on-the-go accountability and goal tracking.
- 🥏 **iOS App**: An intuitive and powerful mobile app for iPhone and iPad users.
- 🌐 **MCP Server**: A centralized server built on the Model Context Protocol (MCP) that powers cross-platform communication and context-aware intelligence.
- 🧹 **Modular SDK**: A pluggable architecture that lets developers integrate Cortex functionality into their own apps and systems.

More integrations and platform support coming soon!
