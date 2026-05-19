// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentIsland",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AgentIsland",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        ),
        .testTarget(
            name: "AgentIslandTests",
            dependencies: ["AgentIsland"],
            path: "Tests"
        )
    ]
)
