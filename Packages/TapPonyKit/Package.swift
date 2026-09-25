// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TapPonyKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "TapPonyKit", targets: ["TapPonyKit"]),
    ],
    targets: [
        .target(name: "TapPonyKit"),
        .testTarget(name: "TapPonyKitTests", dependencies: ["TapPonyKit"]),
    ]
)
