// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Pulse", platforms: [.macOS(.v26)],
    products: [.executable(name: "Pulse", targets: ["PulseApp"])],
    targets: [
        .target(name: "CSensors", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "PulseCore", dependencies: ["CSensors"]),
        .executableTarget(name: "PulseApp", dependencies: ["PulseCore"]),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore", "PulseApp"])
    ]
)
