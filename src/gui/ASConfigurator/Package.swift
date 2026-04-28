// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleSharpenerConfigurator",
    platforms: [
        .macOS(.v15)   // Tahoe: enables .glassEffect() SwiftUI modifier
    ],
    dependencies: [
        .package(url: "https://github.com/danini-the-panini/kdl-swift.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "AppleSharpenerConfigurator",
            dependencies: [
                .product(name: "KDL", package: "kdl-swift")
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ]
)
