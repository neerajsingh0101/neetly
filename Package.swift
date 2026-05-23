// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "neetly",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // libghostty — the terminal engine behind neetly-app's terminal.
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "1.1.4"),
    ],
    targets: [
        .executableTarget(
            name: "neetly-app",
            dependencies: [
                "SwiftTerm",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyTheme", package: "libghostty-spm"),
            ],
            path: "Sources/NeetlyApp",
            resources: [
                .copy("Resources/AppIcon.icns"),
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedLibrary("c++"),
            ]
        ),
        .executableTarget(
            name: "neetly",
            path: "Sources/NeetlyCLI"
        ),
    ]
)
