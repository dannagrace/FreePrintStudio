// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FreePrintStudio",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FreePrintStudioCore",
            targets: ["FreePrintStudioCore"]
        ),
        .executable(
            name: "FreePrintStudioCoreChecks",
            targets: ["FreePrintStudioCoreChecks"]
        ),
    ],
    targets: [
        .target(
            name: "FreePrintStudioCore"
        ),
        .executableTarget(
            name: "FreePrintStudioCoreChecks",
            dependencies: ["FreePrintStudioCore"]
        ),
        .testTarget(
            name: "FreePrintStudioCoreTests",
            dependencies: ["FreePrintStudioCore"]
        ),
    ]
)
