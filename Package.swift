// swift-tools-version: 6.4
import PackageDescription

// Cardano TxWorkshop — inspect, validate, build, sign and submit Cardano transactions.
//
//   • TxWorkshopCore    — platform-neutral: the document format, models, provider
//                         settings, design system. Depends on swift-cardano-core only.
//   • TxWorkshopEngine  — decoding, inspection, validation and chain providers over the
//                         swift-cardano-* stack.
//   • TxWorkshopUI      — the SwiftUI app: document scene, adaptive shell, features.
//   • TxWorkshopDirect  — what only the Developer ID build may do: a local node, cardano-cli.
//
// The installable apps are XcodeGen targets under App/ and AppDirect/ (project.yml).
let package = Package(
    name: "TxWorkshop",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "TxWorkshopCore", targets: ["TxWorkshopCore"]),
        .library(name: "TxWorkshopEngine", targets: ["TxWorkshopEngine"]),
        .library(name: "TxWorkshopUI", targets: ["TxWorkshopUI"]),
        .library(name: "TxWorkshopDirect", targets: ["TxWorkshopDirect"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-core.git", from: "0.8.5"),
        // NodeSocket adds the local-node chain context, on macOS only. Not CLIBackends: that brings
        // swift-cardano-utils, whose swift-configuration needs a swift-collections the Keystone pin
        // below rules out. The cardano-cli provider runs cardano-cli itself instead.
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-chain.git", from: "0.12.0", traits: [.defaults, "NodeSocket"]),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.8.1"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-txvalidator.git", from: "0.5.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-explorers.git", from: "0.1.1"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cddl.git", from: "0.2.3"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-uplc.git", from: "0.8.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "6.0.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-txbuilder.git", from: "1.2.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-cips.git", from: "0.4.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-token-registry.git", from: "0.2.1"),
        // swift-cardano-hw-wallet's Keystone SDK brings a target named `SortedCollections`, as
        // swift-collections does from 1.2: two same-named targets are an SPM error, so hold 1.1.x.
        .package(url: "https://github.com/apple/swift-collections.git", "1.1.0" ..< "1.2.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-hw-wallet.git", from: "0.2.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-nacl.git", .upToNextMinor(from: "1.0.2")),
    ],
    targets: [
        .target(
            name: "TxWorkshopCore",
            dependencies: [
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "TxWorkshopEngine",
            dependencies: [
                "TxWorkshopCore",
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
                .product(name: "SwiftCardanoChain", package: "swift-cardano-chain"),
                .product(name: "SystemPackage", package: "swift-system", condition: .when(platforms: [.macOS])),
                .product(name: "SwiftCardanoTxValidator", package: "swift-cardano-txvalidator"),
                .product(name: "SwiftCDDL", package: "swift-cddl"),
                .product(name: "SwiftCDDLCardano", package: "swift-cddl"),
                .product(name: "SwiftCardanoUPLC", package: "swift-cardano-uplc"),
                .product(name: "SwiftCardanoTokenRegistryClient", package: "swift-cardano-token-registry"),
                .product(name: "SwiftCardanoTxBuilder", package: "swift-cardano-txbuilder"),
                .product(name: "SwiftCardanoCIP21", package: "swift-cardano-cips"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "CardanoHWKit", package: "swift-cardano-hw-wallet"),
                .product(name: "CardanoHWWalletLedger", package: "swift-cardano-hw-wallet"),
                .product(name: "CardanoHWWalletTrezor", package: "swift-cardano-hw-wallet"),
                .product(name: "CardanoHWWalletKeystone", package: "swift-cardano-hw-wallet"),
                .product(name: "SwiftNaCl", package: "swift-nacl"),
            ]
        ),
        .target(
            name: "TxWorkshopUI",
            dependencies: [
                "TxWorkshopCore",
                "TxWorkshopEngine",
                .product(name: "SwiftCardanoTxValidator", package: "swift-cardano-txvalidator"),
                .product(name: "SwiftCardanoExplorers", package: "swift-cardano-explorers"),
                .product(name: "CardanoHWKit", package: "swift-cardano-hw-wallet"),
                .product(name: "CardanoHWWalletKeystone", package: "swift-cardano-hw-wallet", condition: .when(platforms: [.iOS])),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "TxWorkshopDirect",
            dependencies: ["TxWorkshopCore", "TxWorkshopEngine"]
        ),
        .testTarget(
            name: "TxWorkshopCoreTests",
            dependencies: ["TxWorkshopCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "TxWorkshopUITests",
            dependencies: ["TxWorkshopUI", "TxWorkshopEngine", "TxWorkshopCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "TxWorkshopEngineTests",
            dependencies: ["TxWorkshopEngine", "TxWorkshopCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
