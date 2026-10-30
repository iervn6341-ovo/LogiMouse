// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LogiMouse",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "LogiMouse",
            path: "Sources/LogiMouse",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
