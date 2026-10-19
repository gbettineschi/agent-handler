import Testing
@testable import CodexDesktopAdapter

struct ProjectionBudgetTests {
    @Test func rejectsLargeDeepAndAggregateStates() throws {
        let state = JSONValue.object(["text": .string(String(repeating: "a", count: 200))])
        let cost = try #require(ProjectionBudget.cost(state, available: 1024))
        #expect(cost > 200)
        #expect(ProjectionBudget.cost(state, available: cost - 1) == nil)
        #expect(ProjectionBudget.cost(state, available: cost) == cost)
        #expect(ProjectionBudget.cost(.array([state, state]), available: cost) == nil)
        var deep = JSONValue.null
        for _ in 0..<130 { deep = .array([deep]) }
        #expect(ProjectionBudget.cost(deep, available: 100_000) == nil)
    }
}
