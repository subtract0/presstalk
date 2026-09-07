// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "JarvisTap",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "presstalk-capture-probe", targets: ["PressTalkCaptureProbe"]),
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
        // Never bundled into the app: the app holds only public keys.
        .executable(
            name: "presstalk-license",
            targets: ["PressTalkLicenseTool"]
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
        .target(name: "PressTalkHAL", linkerSettings: [
            .linkedFramework("AudioToolbox"), .linkedFramework("CoreAudio"),
        ]),
        .target(name: "PressTalkCapture", dependencies: ["PressTalkHAL"]),
        .executableTarget(name: "PressTalkCaptureProbe", dependencies: ["PressTalkCapture"]),
        .testTarget(name: "PressTalkCaptureTests", dependencies: ["PressTalkCapture", "PressTalkHAL"]),
        .target(
            name: "PressTalkCore",
            dependencies: [],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "JarvisTap",
            dependencies: [
                "PressTalkCapture",
                "PressTalkCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                "WhisperKit",
            ]
        ),
        .executableTarget(
            name: "PressTalkInputMethod",
            dependencies: []
        ),
        .testTarget(
            name: "PressTalkCoreTests",
            dependencies: ["PressTalkCore"]
        ),
        .executableTarget(
            name: "PressTalkLicenseTool",
            dependencies: ["PressTalkCore"]
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
