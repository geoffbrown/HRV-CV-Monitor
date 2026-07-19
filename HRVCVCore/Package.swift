// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HRVCVCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "HRVCVCore", targets: ["HRVCVCore"]),
    ],
    targets: [
        .target(name: "HRVCVCore"),
    ]
)
