import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

struct DesktopProjectionTests {
    // Live long conversations carry megabytes of hook-run metadata outside items.
    // Keeping it must not prevent delivery of otherwise small, valid questions.
    @Test(arguments: [false, true]) func unusedTurnMetadataCannotExhaustQuestionBudget(canonical: Bool) throws {
        var state = try JSONValue.parse(fixtureState(canonical: canonical))
        let turn = Array(itemsPath(canonical).dropLast())
        let hooks = JSONValue.array((0..<900).map { _ in .object(["output": .string(String(repeating: "x", count: 10_000))]) })
        try DesktopPatches.apply([patch("add", turn + [.string("hookRuns")], hooks)], to: &state)
        let expected = try questions(state)
        DesktopProjection.compact(&state)
        #expect(ProjectionBudget.cost(state, available: ProjectionBudget.total) != nil)
        #expect(try questions(state) == expected)
        try DesktopPatches.apply([
            patch("replace", turn + [.string("hookRuns"), .integer(0), .string("output")], .string("Changed")),
            patch("replace", itemsPath(canonical) + [.integer(0), .string("questions"), .integer(0), .string("title")], .string("Still live?"))
        ], to: &state)
        DesktopProjection.compact(&state)
        #expect(ProjectionBudget.cost(state, available: ProjectionBudget.total) != nil)
        #expect(try questions(state).first?.title == "Still live?")
    }
    private func patch(_ op: String, _ path: [JSONValue], _ value: JSONValue = .null) -> JSONValue {
        .object(["op": .string(op), "path": .array(path), "value": value])
    }
    private func itemsPath(_ canonical: Bool) -> [JSONValue] {
        canonical
            ? [.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string("turn-key"), .string("items")]
            : [.string("turns"), .integer(0), .string("items")]
    }
    private func questions(_ state: JSONValue) throws -> [AttentionRequest] {
        try DesktopQuestions.parse(state: state, threadID: "thread", owner: "desktop-owner", installation: "fixture")
    }

    // Catches discarded data corrupting array positions, question identity or replacement semantics.
    // The unprojected native state is the reference; expected requests do not come from the projection.
    @Test(arguments: [false, true]) func mutationsPreserveNativeQuestionMeaning(canonical: Bool) throws {
        var original = try JSONValue.parse(fixtureState(canonical: canonical, extraItems: [
            ["type": "commandExecution", "id": "tool", "output": ["blocks": [["text": "Tool output"]]]]
        ]))
        var projected = original
        DesktopProjection.compact(&projected)
        let identity = try questions(original).map(\.key)
        let base = itemsPath(canonical)
        let tool = JSONValue.object(["type": .string("commandExecution"), "id": .string("tool"),
            "output": .object(["blocks": .array([.object(["text": .string("Replacement output")])])])])
        let replacementItems = try JSONValue.parse(fixtureState(extraItems: [
            ["type": "commandExecution", "id": "tool", "output": ["blocks": [["text": "Tool output"]]]]
        ]))["turns"].arrayValue![0]["items"]
        let batches = [
            [patch("replace", base + [.integer(1), .string("output"), .string("blocks"), .integer(0), .string("text")], .string("Changed"))],
            [patch("remove", base + [.integer(1), .string("output")]),
             patch("add", base + [.integer(1), .string("output")], .object(["x": .array([.integer(1), .integer(2)])])),
             patch("remove", base + [.integer(1), .string("output"), .string("x"), .integer(0)])],
            [patch("replace", base + [.integer(1)], tool),
             patch("replace", base + [.integer(1), .string("output"), .string("blocks"), .integer(0), .string("text")], .string("Changed again"))],
            [patch("add", base + [.integer(0)], tool), patch("remove", base + [.integer(2)])],
            [patch("replace", base + [.integer(1), .string("questions"), .integer(0), .string("title")], .string("Updated?"))],
            [patch("replace", base, replacementItems),
             patch("replace", base + [.integer(1), .string("output"), .string("blocks"), .integer(0), .string("text")], .string("After array replacement"))]
        ]
        for batch in batches {
            try DesktopPatches.apply(batch, to: &original)
            try DesktopPatches.apply(batch, to: &projected)
            DesktopProjection.compact(&projected)
            #expect(try questions(projected) == questions(original))
            #expect(try questions(projected).map(\.key) == identity)
        }
        let whole = [patch("replace", [], original),
                     patch("replace", base + [.integer(0), .string("questions"), .integer(0), .string("title")], .string("After root replacement?"))]
        try DesktopPatches.apply(whole, to: &original)
        try DesktopPatches.apply(whole, to: &projected)
        DesktopProjection.compact(&projected)
        #expect(try questions(projected) == questions(original))
        #expect(try questions(projected).first?.title == "After root replacement?")
    }

    // Catches confusing deliberately unused data with missing or newly required question fields.
    @Test(arguments: [false, true]) func requiredDataStillFailsClosed(canonical: Bool) throws {
        var projected = try JSONValue.parse(fixtureState(canonical: canonical))
        DesktopProjection.compact(&projected)
        let item = itemsPath(canonical) + [.integer(0)]
        for malformed in [
            patch("replace", item + [.string("questions"), .integer(0), .string("options")], .omitted),
            patch("replace", item + [.string("type")], .string("unknown")),
            patch("add", item + [.string("questions"), .integer(0), .string("newRequiredField")], .string("value"))
        ] {
            var bad = projected
            try DesktopPatches.apply([malformed], to: &bad)
            DesktopProjection.compact(&bad)
            #expect(throws: (any Error).self) { _ = try questions(bad) }
        }
        try DesktopPatches.apply([patch("replace", item + [.string("questions")], .omitted)], to: &projected)
        DesktopProjection.compact(&projected)
        #expect(throws: (any Error).self) {
            try DesktopPatches.apply([patch("replace", item + [.string("questions"), .integer(0), .string("title")], .string("Must fail"))], to: &projected)
        }
    }
}
