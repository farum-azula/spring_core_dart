// swift-tools-version: 5.9
// The iOS and macOS part of spring_boot_starter_flutter_security for Swift Package
// Manager (CocoaPods: ../spring_boot_starter_flutter_security.podspec).

import PackageDescription

let package = Package(
    name: "spring_boot_starter_flutter_security",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15"),
    ],
    products: [
        .library(name: "spring-boot-starter-flutter-security", targets: ["spring_boot_starter_flutter_security"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "spring_boot_starter_flutter_security",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
