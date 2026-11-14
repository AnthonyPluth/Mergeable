// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MergeableCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "MergeableCore", targets: ["MergeableCore"])],
    targets: [
        .target(name: "MergeableCore"),
        .testTarget(name: "MergeableCoreTests", dependencies: ["MergeableCore"], resources: [.copy("Fixtures")]),
    ]
)
