// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "cortex-mcp",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "cortex-mcp", targets: ["CortexMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.7.1"),
    ],
    targets: [
        .executableTarget(name: "CortexMCP", dependencies: [
            .product(name: "MCP", package: "swift-sdk")
        ]),
    ]
)
