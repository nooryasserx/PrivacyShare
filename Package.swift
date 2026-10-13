// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PrivacyShare",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "PrivacyShare", path: "Sources/PrivacyShare")
    ]
)
