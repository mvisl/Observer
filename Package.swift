// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Observer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ObserverApp", targets: ["ObserverApp"])
    ],
    targets: [
        .executableTarget(
            name: "ObserverApp",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ObserverAppTests",
            dependencies: ["ObserverApp"]
        )
    ]
)
