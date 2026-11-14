// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Peeky",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Peeky",
            path: "Sources/Peeky",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
