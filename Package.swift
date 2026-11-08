// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlamoTranslate",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "PlamoTranslate", targets: ["PlamoTranslate"])],
    targets: [
        .executableTarget(name: "PlamoTranslate", resources: [.process("Resources")]),
        .testTarget(name: "PlamoTranslateTests", dependencies: ["PlamoTranslate"])
    ],
    swiftLanguageModes: [.v5]
)
