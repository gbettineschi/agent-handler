import Foundation
import Testing
import CSQLite
@testable import CodexDesktopAdapter

struct DiscoveryTests {
    @Test func boundedReadOnlyDiscoveryAndMissingMetadata() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ah-discovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: (any Error).self) { _ = try ThreadDiscovery.candidates(directory: folder) }
        var db: OpaquePointer?
        #expect(sqlite3_open(folder.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TABLE threads(id TEXT,title TEXT,updated_at INTEGER,archived INTEGER,has_user_event INTEGER)", nil, nil, nil) == SQLITE_OK)
        for i in 0..<25 {
            #expect(sqlite3_exec(db, "INSERT INTO threads VALUES('thread-\(i)','Title',\(i),0,1)", nil, nil, nil) == SQLITE_OK)
        }
        // Desktop currently leaves this flag at zero even on ordinary user conversations.
        #expect(sqlite3_exec(db, "INSERT INTO threads VALUES('archived','Hidden',999,1,1),('desktop','Desktop',998,0,0)", nil, nil, nil) == SQLITE_OK)
        let candidates = try ThreadDiscovery.candidates(directory: folder)
        #expect(candidates.count == 16)
        #expect(candidates.first?.id == "desktop")
        #expect(!candidates.map(\.id).contains("archived"))
    }
    @Test func lockedCatalogIsDiagnosedAndRecoversAfterUnlock() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ah-discovery-lock-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var db: OpaquePointer?
        #expect(sqlite3_open(folder.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TABLE threads(id TEXT,title TEXT,updated_at INTEGER,archived INTEGER); INSERT INTO threads VALUES('active','Title',1,0)", nil, nil, nil) == SQLITE_OK)
        #expect(try ThreadDiscovery.candidates(directory: folder).count == 1)
        #expect(sqlite3_exec(db, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        do {
            _ = try ThreadDiscovery.candidates(directory: folder)
            Issue.record("An exclusive catalog lock should be reported")
        } catch {
            #expect(String(describing: error).contains("busy"))
        }
        #expect(sqlite3_exec(db, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        #expect(try ThreadDiscovery.candidates(directory: folder).first?.id == "active")
    }

}
