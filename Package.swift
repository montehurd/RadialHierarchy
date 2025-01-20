// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RadialHierarchy",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/montehurd/HierarchyStringParser.git", from: "1.0.6")
    ],
    targets: [
        .executableTarget(
            name: "RadialHierarchy",
            dependencies: ["HierarchyStringParser"],
            path: "Sources"
        )
    ]
)