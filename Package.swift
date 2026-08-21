// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Prompty",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Prompty", targets: ["Prompty"])
    ],
    targets: [
        .executableTarget(
            name: "Prompty",
            path: "Sources/Prompty"
        )
    ]
)
