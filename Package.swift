// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "neetly",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // libghostty terminal engine — referenced ONLY by the isolated
        // `neetly-ghostty-lab` target below, never by `neetly-app`.
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "1.1.4"),
    ],
    targets: [
        .executableTarget(
            name: "neetly-app",
            dependencies: [
                "SwiftTerm",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
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
        // Isolated libghostty spike — a standalone window with one ghostty
        // terminal. Does NOT touch `neetly-app`; build it explicitly with
        // `swift build --product neetly-ghostty-lab`.
        .executableTarget(
            name: "neetly-ghostty-lab",
            dependencies: [
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
            ],
            path: "Sources/NeetlyGhosttyLab",
            linkerSettings: [
                .linkedFramework("AppKit"),
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
    ]
)
