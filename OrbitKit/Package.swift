// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OrbitKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OrbitCore", targets: ["OrbitCore"]),
        .library(name: "SpotifyKit", targets: ["SpotifyKit"]),
        .library(name: "OrbitEngine", targets: ["OrbitEngine"]),
        .library(name: "OrbitUI", targets: ["OrbitUI"]),
        .library(name: "OrbitShell", targets: ["OrbitShell"]),
        .library(name: "OrbitMocks", targets: ["OrbitMocks"]),
    ],
    targets: [
        .target(name: "OrbitCore"),
        .target(name: "SpotifyKit", dependencies: ["OrbitCore"]),
        .target(name: "OrbitEngine", dependencies: ["OrbitCore"]),
        .target(name: "OrbitMocks", dependencies: ["OrbitCore"]),
        // OrbitMocks is linked into OrbitUI only so #Preview blocks can use fixtures.
        .target(name: "OrbitUI", dependencies: ["OrbitCore", "OrbitEngine", "OrbitMocks"]),
        .target(
            name: "OrbitShell",
            dependencies: ["OrbitCore", "SpotifyKit", "OrbitEngine", "OrbitUI", "OrbitMocks"]
        ),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"]),
        .testTarget(name: "SpotifyKitTests", dependencies: ["SpotifyKit", "OrbitCore"]),
        .testTarget(name: "OrbitEngineTests", dependencies: ["OrbitEngine", "OrbitCore", "OrbitMocks"]),
        .testTarget(name: "OrbitShellTests", dependencies: ["OrbitShell", "OrbitCore"]),
    ],
    swiftLanguageModes: [.v6]
)
