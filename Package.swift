// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ServiceWatch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ServiceWatch", targets: ["ServiceWatch"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(name: "ServiceWatch", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .testTarget(name: "ServiceWatchTests", dependencies: ["ServiceWatch"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
