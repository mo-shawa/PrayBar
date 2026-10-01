// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PrayBarCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "PrayBarCore", targets: ["PrayBarCore"])],
    dependencies: [
        .package(url: "https://github.com/batoulapps/adhan-swift.git", exact: "1.5.0")
    ],
    targets: [
        .target(name: "PrayBarCore", dependencies: [.product(name: "Adhan", package: "adhan-swift")]),
        .testTarget(name: "PrayBarCoreTests", dependencies: ["PrayBarCore", .product(name: "Adhan", package: "adhan-swift")])
    ]
)
