// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "nanoleaf",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "nanoleaf", targets: ["nanoleaf"])],
    targets: [
        .target(name: "NanoleafCore"),
        .executableTarget(name: "nanoleaf", dependencies: ["NanoleafCore"]),
        .executableTarget(name: "NanoleafChecks", dependencies: ["NanoleafCore"], path: "Tests/NanoleafCoreTests")
    ]
)
