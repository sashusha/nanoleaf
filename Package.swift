// swift-tools-version: 5.9
import PackageDescription
import Foundation

let locationInfo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Support/Info.plist").path

let package = Package(
    name: "nanoleaf",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "nanoleaf", targets: ["nanoleaf"])],
    targets: [
        .target(name: "NanoleafCore"),
        .executableTarget(name: "nanoleaf", dependencies: ["NanoleafCore"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", locationInfo])]),
        .executableTarget(name: "NanoleafChecks", dependencies: ["NanoleafCore"], path: "Tests/NanoleafCoreTests")
    ]
)
