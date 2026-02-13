// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AntennaProtocol",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "AntennaProtocol", targets: ["AntennaProtocol"])
    ],
    dependencies: [
        // No external dependencies by default. Integrators can add web3/WalletConnect stacks in their app layer.
    ],
    targets: [
        .target(
            name: "AntennaProtocol",
            dependencies: [],
            path: "Sources/AntennaProtocol"
        ),
        .testTarget(
            name: "AntennaProtocolTests",
            dependencies: ["AntennaProtocol"],
            path: "Tests/AntennaProtocolTests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
