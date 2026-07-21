// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MachOMerger",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(
            name: "MachOMerger",
            targets: ["MachOMerger"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/pinauten/SwiftUtils", branch: "master"),
        .package(url: "https://github.com/pinauten/SwiftMachO", branch: "master"),
        .package(url: "https://github.com/pinauten/PatchfinderUtils", branch: "master")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "MachOMerger",
            dependencies: ["SwiftUtils", "SwiftMachO", "PatchfinderUtils"]),
    ]
)
