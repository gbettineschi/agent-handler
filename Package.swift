// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentHandler", platforms: [.macOS(.v14)],
    products: [.library(name: "AgentHandlerCore", targets: ["AgentHandlerCore"])],
    targets: [
        .target(name: "AgentHandlerCore"),
        .testTarget(name: "AgentHandlerCoreTests", dependencies: ["AgentHandlerCore"])
    ], swiftLanguageModes: [.v6]
)
