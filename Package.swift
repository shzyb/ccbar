// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CCBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "CCBarCore",
            path: "Sources/CCBarCore"
        ),
        .executableTarget(
            name: "CCBarApp",
            dependencies: ["CCBarCore"],
            path: "Sources/CCBarApp",
            exclude: ["Info.plist"]
        ),
        .executableTarget(
            name: "CCBarAppTests",
            dependencies: ["CCBarCore"],
            path: "Sources/CCBarAppTests"
        )
    ]
)
