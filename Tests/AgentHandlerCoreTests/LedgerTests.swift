import Foundation
import Testing
import CSQLite
@testable import AgentHandlerCore

func temporaryDatabase() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ah-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("ledger.sqlite")
}
struct LedgerTests {
    @Test func secondInstanceCannotOwnSameBroker() throws {
        let url = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = try InstanceLock(url: url.appendingPathExtension("lock"))
        _ = withExtendedLifetime(first) {
            #expect(throws: (any Error).self) { _ = try InstanceLock(url: url.appendingPathExtension("lock")) }
        }
    }
    @Test func unavailableStorageIsRejected() throws {
        let url = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(throws: (any Error).self) { _ = try SQLiteLedger(url: url.deletingLastPathComponent()) }
    }
    @Test func reservationSurvivesRestartAndFingerprintChange() throws {
        let url = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let q = question(), id = UUID()
        do { let ledger = try SQLiteLedger(url: url); try ledger.reserve(key: q.key, fingerprint: q.fingerprint, attemptID: id) }
        let reopened = try SQLiteLedger(url: url)
        #expect(try reopened.status(for: q.key)?.status == .uncertain)
        #expect(throws: ResponseError.self) { try reopened.reserve(key: q.key, fingerprint: "different", attemptID: UUID()) }
    }
    @Test func acceptedPersistsAndStaleAttemptCannotOverwrite() throws {
        let url = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let q = question(), id = UUID()
        do {
            let ledger = try SQLiteLedger(url: url)
            try ledger.reserve(key: q.key, fingerprint: q.fingerprint, attemptID: id)
            try ledger.finish(key: q.key, attemptID: UUID(), outcome: .accepted)
            #expect(try ledger.status(for: q.key)?.status == .inFlight)
            try ledger.finish(key: q.key, attemptID: id, outcome: .accepted)
        }
        let reopened = try SQLiteLedger(url: url)
        #expect(try reopened.status(for: q.key)?.status == .accepted)
        #expect(throws: ResponseError.self) { try reopened.reserve(key: q.key, fingerprint: q.fingerprint, attemptID: UUID()) }
    }
    @Test func definitelyNotSentAllowsNewAttempt() throws {
        let url = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try SQLiteLedger(url: url), q = question(), first = UUID(), second = UUID()
        try ledger.reserve(key: q.key, fingerprint: q.fingerprint, attemptID: first)
        try ledger.finish(key: q.key, attemptID: first, outcome: .notSent)
        try ledger.reserve(key: q.key, fingerprint: q.fingerprint, attemptID: second)
        try ledger.finish(key: q.key, attemptID: first, outcome: .accepted)
        #expect(try ledger.status(for: q.key)?.attemptID == second)
        #expect(try ledger.status(for: q.key)?.status == .inFlight)
    }
    @Test func futureSchemaIsRejected() throws {
        let url = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA user_version=2", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        #expect(throws: (any Error).self) { _ = try SQLiteLedger(url: url) }
    }
    @Test func storesHashesAndNoQuestionContent() throws {
        let url = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let q = question(title: "PRIVATE_QUESTION_MARKER")
        do { let ledger = try SQLiteLedger(url: url); try ledger.reserve(key: q.key, fingerprint: q.fingerprint, attemptID: UUID()) }
        let bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data("PRIVATE_QUESTION_MARKER".utf8)) == nil)
        #expect(bytes.range(of: Data("fixture".utf8)) == nil)
    }
}
