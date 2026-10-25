// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RepoRadar",
    platforms: [.macOS("26.0")],  // Liquid Glass APIs (glassEffect, .glass button styles)
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "RepoRadar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/RepoRadar",
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")],  // /regex/ literals
            // Sparkle.framework sits in Contents/Frameworks of the app bundle.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "RepoRadarTests", dependencies: ["RepoRadar"], path: "Tests/RepoRadarTests")
    ]
)
