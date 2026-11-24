// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CentraleMac",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Bibliothèque principale contenant les modèles, services et vues (testable par CentraleMacTests).
        .library(
            name: "CentraleMacCore",
            targets: ["CentraleMacCore"]
        ),
        // Exécutable macOS ouvrant la fenêtre SwiftUI de la centrale.
        .executable(
            name: "CentraleMacApp",
            targets: ["CentraleMacApp"]
        )
    ],
    targets: [
        .target(
            name: "CentraleMacCore",
            path: ".",
            exclude: [
                "App",
                "Tests",
                "Package.swift"
            ],
            sources: [
                "Models",
                "Services",
                "ViewModels",
                "Views"
            ]
        ),
        .executableTarget(
            name: "CentraleMacApp",
            dependencies: ["CentraleMacCore"],
            path: "App"
        ),
        .testTarget(
            name: "CentraleMacTests",
            dependencies: ["CentraleMacCore"],
            path: "Tests"
        )
    ]
)
