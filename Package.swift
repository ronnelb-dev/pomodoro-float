// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CubeTimer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CubeTimer", targets: ["CubeTimer"])],
    targets: [
        .executableTarget(name: "CubeTimer", resources: [.process("Resources")]),
        .testTarget(name: "CubeTimerTests", dependencies: ["CubeTimer"])
    ]
)
