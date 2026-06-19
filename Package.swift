// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RepoRadar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "RepoRadar",
            path: "Sources/RepoRadar",
            resources: [
                .process("Resources")
            ]
            // For hot reloading later, add:
            // linkerSettings: [.unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug))]
        )
    ]
)
