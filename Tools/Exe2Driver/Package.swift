// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Exe2Driver",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(
            name: "Exe2Driver",
            targets: ["Exe2Driver"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(name: "SwiftUtils", url: "https://github.com/pinauten/SwiftUtils", .branch("master")),
        .package(name: "SwiftMachO", url: "https://github.com/pinauten/SwiftMachO", .branch("master"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Exe2Driver",
            dependencies: ["SwiftUtils", "SwiftMachO"])
    ]
)
