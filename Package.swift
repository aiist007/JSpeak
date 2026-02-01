// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JSpeak",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "JSpeakCore", targets: ["JSpeakCore"]),
        .library(name: "JSpeakPythonBridge", targets: ["JSpeakPythonBridge"]),
        .executable(name: "jspeak", targets: ["JSpeakCLI"]),
        .executable(name: "jspeak-ime-host", targets: ["JSpeakIMEHost"]),
    ],
    targets: [
        .target(
            name: "JSpeakCore"
        ),
        .target(
            name: "JSpeakPythonBridge",
            dependencies: ["JSpeakCore"]
        ),
        .executableTarget(
            name: "JSpeakCLI",
            dependencies: ["JSpeakPythonBridge"]
        ),
        .executableTarget(
            name: "JSpeakIMEHost",
            dependencies: ["JSpeakPythonBridge"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("InputMethodKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ]
)
