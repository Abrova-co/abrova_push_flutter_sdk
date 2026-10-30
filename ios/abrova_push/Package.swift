// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "abrova_push",
    platforms: [.iOS("13.0")],
    products: [
        .library(name: "abrova-push", targets: ["abrova_push"])
    ],
    dependencies: [
        .package(url: "https://center.abrova.ir/abrova/abrova-push-ios-sdk.git", from: "0.1.18")
    ],
    targets: [
        // Objective-C code: Swift Package Manager builds it as its own target.
        .target(
            name: "abrova_push_objc",
            path: "Sources/abrova_push_objc"
        ),
        .target(
            name: "abrova_push",
            dependencies: ["abrova_push_objc", .product(name: "AbrovaPush", package: "abrova-push-ios-sdk")]
        )
    ]
)
