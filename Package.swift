// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "neetly",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "neetly-app",
            dependencies: [
                "SwiftTerm",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/NeetlyApp",
            linkerSettings: [
                .linkedFramework("WebKit"),
            ]
        ),
        .executableTarget(
            name: "neetly",
            path: "Sources/NeetlyCLI"
        ),
    ]
)
