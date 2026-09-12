// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "OpenlistMCP",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OpenlistMCP", type: .static, targets: ["OpenlistMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.102.0"),
    ],
    targets: [
        .target(
            name: "OpenlistMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ],
            path: "MCPTransport"
        ),
        .testTarget(
            name: "OpenlistMCPTests",
            dependencies: [
                "OpenlistMCP",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            path: "Tools/MCPTransportTests"
        ),
    ]
)
