// swift-tools-version: 6.0
import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "Bitlathe",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BitlatheCore", targets: ["BitlatheCore"]),
        .library(name: "BitlatheUI", targets: ["BitlatheUI"]),
        .library(name: "BitlatheTools", targets: ["BitlatheTools"]),
        .executable(name: "bl", targets: ["BitlatheCLI"]),
        .executable(name: "bl-advisor", targets: ["BitlatheAdvisor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "5.4.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "BitlatheCore",
            path: "Sources/BitlatheCore",
            swiftSettings: strict,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "BitlatheUI",
            dependencies: ["BitlatheCore"],
            path: "Sources/BitlatheUI",
            swiftSettings: strict
        ),
        .target(
            name: "BitlatheTools",
            dependencies: [
                "BitlatheCore", "BitlatheUI",
                .product(name: "Yams", package: "Yams"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/BitlatheTools",
            resources: [.copy("Resources")],
            swiftSettings: strict,
            linkerSettings: [.linkedLibrary("z"), .linkedLibrary("compression")]
        ),
        .executableTarget(
            name: "BitlatheCLI",
            dependencies: ["BitlatheCore", "BitlatheTools"],
            path: "Sources/BitlatheCLI",
            swiftSettings: strict
        ),
        // The on-device model helper. No dependencies on purpose: it must build with a toolchain that has the
        // FoundationModels SDK even when the rest of the package is built with an older Xcode.
        .executableTarget(
            name: "BitlatheAdvisor",
            path: "Sources/BitlatheAdvisor",
            swiftSettings: strict
        ),
        .testTarget(
            name: "BitlatheTests",
            dependencies: ["BitlatheCore", "BitlatheTools", "BitlatheUI"],
            path: "Tests/BitlatheTests",
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
    ]
)
