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
        .executable(
            name: "presstalk-input-method",
            targets: ["PressTalkInputMethod"]
        ),
        .executable(
            name: "presstalk-asr-bench",
            targets: ["PressTalkAsrBench"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "f3760dc3962626d337548e5ccbfbb5fa6f7cc2e2"
        ),
    ],
    targets: [
        .executableTarget(
            name: "JarvisTap",
            dependencies: [
                "WhisperKit",
            ]
        ),
        .executableTarget(
            name: "PressTalkInputMethod",
            dependencies: []
        ),
        .executableTarget(
            name: "PressTalkAsrBench",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "WhisperKit",
            ]
        ),
    ]
)
