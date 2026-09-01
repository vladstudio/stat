// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Stat",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../app-kit"),
    ],
    targets: [
        .systemLibrary(
            name: "CIOHIDPrivate",
            path: "app/CIOHIDPrivate"
        ),
        .target(
            name: "StatKit",
            dependencies: ["CIOHIDPrivate"],
            path: "app/StatKit"
        ),
        .executableTarget(
            name: "Stat",
            dependencies: [.product(name: "MacAppKit", package: "app-kit"), "StatKit"],
            path: "app/Stat",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "StatKitTests",
            dependencies: ["StatKit"],
            path: "Tests/StatKitTests"
        ),
        .executableTarget(
            name: "TempTest",
            dependencies: ["CIOHIDPrivate"],
            path: "app/TempTest"
        ),
    ]
)
