import Testing
@testable import AgentHandlerApp
@testable import CodexDesktopAdapter

struct DiscoveryCatalogTests {
    @Test func failuresRetainSubscriptionsUntilAnAuthoritativeSuccess() {
        var catalog = DiscoveryCatalog()
        catalog.update(.success([.init(id: "active", title: "Actual title")]))
        for _ in 0..<3 { catalog.update(.failure(ThreadDiscovery.Failure.database(operation: "schema", code: 5))) }
        #expect(catalog.candidates.map(\.id) == ["active"])
        #expect(catalog.candidates.first?.title == "Actual title")
        #expect(catalog.retryNeeded)
        #expect(catalog.diagnostic?.contains("busy") == true)
        #expect(catalog.warning?.contains("automatically") == true)
        catalog.update(.success([]))
        #expect(catalog.candidates.isEmpty)
        #expect(!catalog.retryNeeded)
        #expect(catalog.warning == nil)
    }
    @Test func initialFailureRetriesAndLaterSuccessClearsTheWarning() {
        var catalog = DiscoveryCatalog()
        catalog.update(.failure(ThreadDiscovery.Failure.unavailable))
        #expect(catalog.candidates.isEmpty)
        #expect(catalog.retryNeeded)
        catalog.update(.success([.init(id: "recovered", title: "Recovered chat")]))
        #expect(catalog.candidates.map(\.id) == ["recovered"])
        #expect(!catalog.retryNeeded)
        #expect(catalog.diagnostic == nil)
    }
}
