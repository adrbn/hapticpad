// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Textur",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Textur", targets: ["Textur"]),
    ],
    targets: [
        // Thin C bridge that loads Apple's private MultitouchSupport framework at runtime.
        .target(
            name: "CMultitouch",
            linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("IOKit")]
        ),
        // Pure logic: gestures, materials, textures, sound synthesis, settings. No AppKit.
        .target(name: "TexturCore"),
        // The menu bar app.
        .executableTarget(
            name: "Textur",
            dependencies: ["CMultitouch", "TexturCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "TexturCoreTests", dependencies: ["TexturCore"]),
    ]
)
