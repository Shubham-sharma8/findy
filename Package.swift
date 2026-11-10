// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Findy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Findy", targets: ["Findy"])
    ],
    targets: [
        .executableTarget(
            name: "Findy",
            path: "Sources/Findy",
            resources: [
                .copy("Resources/Logo.png")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Vision"),
                .linkedFramework("AppIntents")
            ]
        ),
        .testTarget(
            name: "FindyTests",
            dependencies: ["Findy"],
            path: "Tests/FindyTests"
        )
    ]
)
