// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "graphexplorer-sync",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.12.0"),
        // SQLite runs the in-memory database used by the test suite.
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.9.0"),
        // `swift package generate-documentation` → Apple-style DocC site.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
        // SHA-256 digests for at-rest token hashing (shared pin with Vapor).
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                // swift-testing support — works on the bare toolchain (no Xcode).
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny")
    ]
}
