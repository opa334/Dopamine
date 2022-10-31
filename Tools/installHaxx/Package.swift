// swift-tools-version:5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "installHaxx",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(
            name: "installHaxx",
            targets: ["installHaxx"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(name: "SwiftUtils", url: "https://github.com/pinauten/SwiftUtils", .branch("master")),
        .package(name: "SwiftMachO", url: "https://github.com/pinauten/SwiftMachO", .branch("master"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "installHaxx",
            dependencies: ["SwiftUtils", "SwiftMachO"]),
    ]
)
