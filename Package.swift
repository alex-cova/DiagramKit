// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DiagramKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DiagramKit", targets: ["DiagramKit"]),
    ],
    targets: [
        .target(
            name: "DiagramKit",
            exclude: [
                "Support/SplitView/LICENSE",
                "Support/SplitView/README.md",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)
