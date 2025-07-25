# Cortex Accountability App

A macOS accountability app built with Tauri 2.0, React, and TypeScript that helps users stay focused by monitoring activity and enforcing natural language rules.

## Features

- **Natural Language Rule Creation**: Create accountability rules using plain English
- **SQLite Database**: Persistent storage for rules and activity logs
- **Chrome Extension**: Browser activity monitoring and UI data extraction
- **React Frontend**: Modern, responsive UI with Tailwind CSS
- **Rust Backend**: High-performance backend with Tauri 2.0

## Quick Start

### Prerequisites

- Node.js (v16 or later)
- Rust (latest stable)
- macOS (for development)

### Installation

1. Install dependencies:
```bash
npm install
```

2. Run in development mode:
```bash
npm run tauri dev
```

3. Build for production:
```bash
npm run tauri build
```

## Project Structure

```
cortex-accountability/
├── src/                    # React frontend
│   ├── components/         # UI components
│   ├── types.ts           # TypeScript interfaces
│   └── main.tsx           # App entry point
├── src-tauri/             # Rust backend
│   ├── src/
│   │   ├── main.rs        # App entry point
│   │   └── database.rs    # SQLite operations
│   └── Cargo.toml         # Rust dependencies
├── browser-extension/     # Chrome extension
│   ├── manifest.json      # Extension manifest
│   ├── background.js      # Service worker
│   ├── content.js         # Content script
│   └── popup.html         # Extension popup
└── package.json           # Node.js dependencies
```

## Chrome Extension Setup

1. Open Chrome and go to `chrome://extensions/`
2. Enable "Developer mode" 
3. Click "Load unpacked" and select the `browser-extension` folder
4. The extension will appear in your toolbar

## Usage

### Creating Rules

1. Open the Cortex app
2. Enter a natural language rule like:
   - "Don't let me scroll on Instagram during work hours"
   - "Block YouTube videos but allow music"
   - "Only allow r/MachineLearning on Reddit"
3. Click "Add Rule" to save

### Managing Rules

- Toggle rules on/off with the checkbox
- View rule details by clicking the expand button
- Delete rules with the trash icon

### Browser Monitoring

The Chrome extension automatically monitors your web activity and reports back to the main app. You can view recent activity in the extension popup.

## Technical Details

### Backend Architecture

- **Tauri 2.0**: Cross-platform app framework
- **SQLite**: Embedded database with SQLx for type-safe queries
- **Tokio**: Async runtime for Rust
- **Serde**: JSON serialization/deserialization

### Frontend Architecture

- **React 18**: Modern React with hooks
- **TypeScript**: Type-safe JavaScript
- **Tailwind CSS**: Utility-first CSS framework
- **Vite**: Fast build tool and dev server

### Browser Extension

- **Manifest V3**: Modern Chrome extension API
- **Content Scripts**: Page-level activity monitoring
- **Service Worker**: Background processing
- **Native Messaging**: Communication with main app (planned)

## Development

### Running Tests

```bash
# Run frontend tests
npm test

# Run backend tests
cargo test
```

### Building for Production

```bash
npm run build
npm run tauri build
```

The built app will be in `src-tauri/target/release/bundle/`.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## License

This project is licensed under the MIT License.