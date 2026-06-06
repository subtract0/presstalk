// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "JarvisTap",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "jarvistap",
            targets: ["JarvisTap"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "JarvisTap",
            dependencies: [
                "WhisperKit",
            ]
        ),
    ]
)
