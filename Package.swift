// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "neetly1",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "neetly1",
            dependencies: ["SwiftTerm"],
            path: "Sources/Neetly1",
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
