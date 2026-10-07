// swift-tools-version: 5.9
import PackageDescription

// run-tests.sh stages exact copies of selected app sources next to this manifest.
// Swift 5 language mode matches the iOS project's current language mode.
var coreDependencies: [Target.Dependency] = []
var supportTargets: [Target] = []
#if os(Linux)
coreDependencies = ["Combine", "CryptoKit", "JavaScriptCore", "SwiftUI"]
supportTargets = [
    .target(name: "Combine", path: "Support/Combine"),
    .target(name: "JavaScriptCore", path: "Support/JavaScriptCore"),
    .target(name: "SwiftUI", dependencies: ["Combine"], path: "Support/SwiftUI"),
    .target(name: "COpenSSL", path: "Support/COpenSSL", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("crypto")]),
    .target(name: "CryptoKit", dependencies: ["COpenSSL"], path: "Support/CryptoKit")
]
#endif
let package = Package(
    name: "BlackGodIntelligenceValidation",
    platforms: [.macOS(.v13)],
    products: [.library(name: "BlackGodCore", targets: ["BlackGodCore"])],
    targets: [
        .target(name: "BlackGodCore", dependencies: coreDependencies, path: "Sources"),
        .testTarget(name: "BlackGodCoreTests", dependencies: ["BlackGodCore"] + coreDependencies, path: "Tests")
    ] + supportTargets
)
