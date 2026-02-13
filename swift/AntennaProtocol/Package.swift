// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AntennaProtocol",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
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
