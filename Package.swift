// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MDbeaty",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MDbeaty", targets: ["MDbeaty"])
    ],
    dependencies: [
        .package(url: "https://github.com/JohnSundell/Ink.git", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "MDbeaty",
            dependencies: [
                "Ink"
            ]
        )
    ]
)
