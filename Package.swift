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
        .executableTarget(name: "AgentHandlerApp", dependencies: ["AgentHandlerCore", "CodexDesktopAdapter"]),
        .executableTarget(name: "AgentHandlerDiagnostics", dependencies: ["AgentHandlerCore", "CodexDesktopAdapter"]),
        .executableTarget(name: "LedgerCrashFixture", dependencies: ["AgentHandlerCore"], path: "Tests/Fixtures/LedgerCrashFixture"),
        .testTarget(name: "AgentHandlerCoreTests", dependencies: ["AgentHandlerCore", "CSQLite", "LedgerCrashFixture"]),
        .testTarget(name: "CodexDesktopAdapterTests", dependencies: ["CodexDesktopAdapter", "AgentHandlerCore", "CSQLite"]),
        .testTarget(name: "AgentHandlerAppTests", dependencies: ["AgentHandlerApp"])
    ], swiftLanguageModes: [.v6]
)
