// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirLingo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AirLingo", targets: ["AirLingo"])
    ],
    targets: [
        .executableTarget(
            name: "AirLingo",
            path: "Sources/AirLingo"
        )
    ]
)
