// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MahjongCore",
    products: [.library(name: "MahjongCore", targets: ["MahjongCore"])],
    targets: [
        .target(name: "MahjongCore"),
        .testTarget(name: "MahjongCoreTests", dependencies: ["MahjongCore"])
    ]
)
