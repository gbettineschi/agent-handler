// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentHandler", platforms: [.macOS(.v14)],
    products: [.library(name: "AgentHandlerCore", targets: ["AgentHandlerCore"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "AgentHandlerCore", dependencies: ["CSQLite"]),
        .testTarget(name: "AgentHandlerCoreTests", dependencies: ["AgentHandlerCore", "CSQLite"])
    ], swiftLanguageModes: [.v6]
)
