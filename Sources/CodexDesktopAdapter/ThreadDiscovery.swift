import Foundation
import CSQLite
import Darwin

public struct ThreadCandidate: Identifiable, Sendable { public let id: String; public let title: String }
public enum ThreadDiscovery {
    public enum Failure: Error, CustomStringConvertible {
        case unavailable, unsupportedSchema
        case database(operation: String, code: Int32)
        case file(operation: String, code: Int32)
        public var description: String {
            switch self {
            case .unavailable: "Conversation catalog file is unavailable"
            case .unsupportedSchema: "Conversation catalog schema is unsupported"
            case .file(let operation, let code): "Conversation catalog file unavailable (\(operation), errno \(code))"
            case .database(let operation, let code):
                "Conversation catalog \((code & 0xff) == SQLITE_BUSY || (code & 0xff) == SQLITE_LOCKED ? "busy" : "read failed") (\(operation), SQLite \(code))"
            }
        }
    }
    public static func candidates(directory: URL, limit: Int = 16) throws -> [ThreadCandidate] {
        guard limit > 0 else { return [] }
        guard let parent = realpath(directory.path, nil) else { throw Failure.file(operation: "directory", code: errno) }
        let path = String(cString: parent) + "/state_5.sqlite"; free(parent)
        var info = stat()
        guard lstat(path, &info) == 0 else { throw Failure.file(operation: "stat", code: errno) }
        guard info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG else { throw Failure.unavailable }
        var db: OpaquePointer?
        let opened = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOFOLLOW, nil)
        defer { sqlite3_close(db) }
        guard opened == SQLITE_OK else { throw Failure.database(operation: "open", code: opened) }
        sqlite3_busy_timeout(db, 100)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &statement, nil) == SQLITE_OK else { throw Failure.database(operation: "schema", code: sqlite3_errcode(db)) }
        var columns: Set<String> = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else {
                sqlite3_finalize(statement)
                throw Failure.database(operation: "schema", code: status)
            }
            if let name = sqlite3_column_text(statement, 1) { columns.insert(String(cString: name)) }
        }
        sqlite3_finalize(statement); statement = nil
        guard Set(["id", "title", "archived", "updated_at"]).isSubset(of: columns) else { throw Failure.unsupportedSchema }
        // has_user_event is not a reliable Desktop visibility flag. Owner discovery is authority.
        let query = "SELECT id,title FROM threads WHERE archived=0 ORDER BY updated_at DESC,id LIMIT ?"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { throw Failure.database(operation: "query", code: sqlite3_errcode(db)) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(min(limit, 16)))
        var result: [ThreadCandidate] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw Failure.database(operation: "read", code: status) }
            guard let idBytes = sqlite3_column_text(statement, 0),
                  let titleBytes = sqlite3_column_text(statement, 1) else { throw Failure.unavailable }
            let id = String(cString: idBytes), title = String(cString: titleBytes)
            guard !id.isEmpty, id.utf8.count <= 256 else { continue }
            if !result.contains(where: { $0.id == id }) { result.append(.init(id: id, title: String(title.prefix(256)))) }
        }
    }
}
