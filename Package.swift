// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "agent-termial",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.18.0"),
    ],
    targets: [
        .target(name: "TermCore", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
        .executableTarget(
            name: "TermApp",
            dependencies: [
                "TermCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(name: "TermCoreTests", dependencies: ["TermCore"]),
    ]
)
