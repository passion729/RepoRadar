// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RepoRadar",
    platforms: [.macOS("26.0")],  // Liquid Glass APIs (glassEffect, .glass button styles)
    targets: [
        .executableTarget(
            name: "RepoRadar",
            path: "Sources/RepoRadar",
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]  // /regex/ literals
        ),
        .testTarget(name: "RepoRadarTests", dependencies: ["RepoRadar"], path: "Tests/RepoRadarTests")
    ]
)
