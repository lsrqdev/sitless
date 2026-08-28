// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StandLessKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "StandLessKit", targets: ["StandLessKit"])
    ],
    targets: [
        .target(name: "StandLessKit"),
        .testTarget(name: "StandLessKitTests", dependencies: ["StandLessKit"])
    ]
)
