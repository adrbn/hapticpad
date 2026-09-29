// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HapticPad",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HapticPad", targets: ["HapticPad"]),
    ],
    targets: [
        // Thin C bridge that loads Apple's private MultitouchSupport framework at runtime.
        .target(
            name: "CMultitouch",
            linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("IOKit")]
        ),
        // Pure logic: gestures, materials, textures, sound synthesis, settings. No AppKit.
        .target(name: "HapticPadCore"),
        // The menu bar app.
        .executableTarget(
            name: "HapticPad",
            dependencies: ["CMultitouch", "HapticPadCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "HapticPadCoreTests", dependencies: ["HapticPadCore"]),
    ]
)
