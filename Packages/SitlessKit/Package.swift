// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SitlessKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "SitlessKit", targets: ["SitlessKit"])
    ],
    targets: [
        .target(name: "SitlessKit"),
        .testTarget(name: "SitlessKitTests", dependencies: ["SitlessKit"])
    ]
)
