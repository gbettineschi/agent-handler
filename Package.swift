// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentHandler", platforms: [.macOS(.v14)],
    products: [.library(name: "AgentHandlerCore", targets: ["AgentHandlerCore"]),
               .library(name: "CodexDesktopAdapter", targets: ["CodexDesktopAdapter"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "AgentHandlerCore", dependencies: ["CSQLite"]),
        .target(name: "CodexDesktopAdapter", dependencies: ["AgentHandlerCore", "CSQLite"]),
        .testTarget(name: "AgentHandlerCoreTests", dependencies: ["AgentHandlerCore", "CSQLite"]),
        .testTarget(name: "CodexDesktopAdapterTests", dependencies: ["CodexDesktopAdapter", "AgentHandlerCore"])
    ], swiftLanguageModes: [.v6]
)
