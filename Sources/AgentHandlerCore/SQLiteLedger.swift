import Foundation
import CSQLite
import Darwin

public final class SQLiteLedger: DeliveryLedger, @unchecked Sendable {
    public enum Failure: Error { case database(Int32, String), schema, unsafeFile }
    private let lock = NSLock()
    private var database: OpaquePointer?
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        // macOS /var and /tmp are symlinks. Resolve only the parent; never follow a substituted ledger file.
        guard let parent = realpath(url.deletingLastPathComponent().path, nil) else { throw Failure.unsafeFile }
        let path = String(cString: parent) + "/" + url.lastPathComponent
        free(parent)
        let descriptor = Darwin.open(path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Failure.unsafeFile }
        var info = stat()
        let safe = fstat(descriptor, &info) == 0 && info.st_uid == getuid() && (info.st_mode & S_IFMT) == S_IFREG
        let protected = safe && fchmod(descriptor, 0o600) == 0
        Darwin.close(descriptor)
        guard protected else { throw Failure.unsafeFile }
        let code = sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        guard code == SQLITE_OK else {
            let detail = String(cString: sqlite3_errmsg(database))
            let extended = sqlite3_extended_errcode(database)
            sqlite3_close(database); database = nil; throw Failure.database(extended, detail)
        }
        do {
            sqlite3_busy_timeout(database, 1000)
            let version = try statement("PRAGMA user_version") { stmt -> Int32 in
                guard sqlite3_step(stmt) == SQLITE_ROW else { throw Failure.schema }
                return sqlite3_column_int(stmt, 0)
            }
            guard version == 0 || version == 1 else { throw Failure.schema }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("CREATE TABLE IF NOT EXISTS attempts (request_key TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, attempt_id TEXT NOT NULL, status TEXT NOT NULL, updated_at REAL NOT NULL)")
                try execute("PRAGMA user_version=1")
                try execute("UPDATE attempts SET status='uncertain' WHERE status='inFlight'")
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        } catch { sqlite3_close(database); database = nil; throw error }
    }
    deinit { sqlite3_close(database) }

    public func reserve(key: RequestKey, fingerprint: String, attemptID: UUID) throws {
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                if let old = try read(key), ![.notSent, .rejected].contains(old.status) { throw ResponseError.alreadySubmitted }
                try run("INSERT INTO attempts VALUES (?,?,?,?,strftime('%s','now')) ON CONFLICT(request_key) DO UPDATE SET fingerprint=excluded.fingerprint, attempt_id=excluded.attempt_id, status=excluded.status, updated_at=excluded.updated_at",
                        [key.digest, fingerprint, attemptID.uuidString, LedgerStatus.inFlight.rawValue])
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }
    public func finish(key: RequestKey, attemptID: UUID, outcome: DeliveryOutcome) throws {
        try lock.withLock {
            try run("UPDATE attempts SET status=?, updated_at=strftime('%s','now') WHERE request_key=? AND attempt_id=? AND status IN ('inFlight','uncertain')",
                    [outcome.rawValue, key.digest, attemptID.uuidString])
        }
    }
    public func status(for key: RequestKey) throws -> LedgerEntry? { try lock.withLock { try read(key) } }
    public func close(key: RequestKey) throws {
        try lock.withLock { try run("UPDATE attempts SET status='closed' WHERE request_key=? AND status!='accepted'", [key.digest]) }
    }
    private func read(_ key: RequestKey) throws -> LedgerEntry? {
        try statement("SELECT fingerprint,attempt_id,status FROM attempts WHERE request_key=?", [key.digest]) { stmt in
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw Failure.database(result, String(cString: sqlite3_errmsg(database))) }
            func column(_ i: Int32) throws -> String {
                guard let bytes = sqlite3_column_text(stmt, i) else { throw Failure.schema }
                return String(cString: bytes)
            }
            guard let id = UUID(uuidString: try column(1)), let status = LedgerStatus(rawValue: try column(2)) else { throw Failure.schema }
            return .init(fingerprint: try column(0), attemptID: id, status: status)
        }
    }
    private func execute(_ sql: String) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw Failure.database(result, String(cString: sqlite3_errmsg(database))) }
    }
    private func run(_ sql: String, _ values: [String]) throws {
        try statement(sql, values) { stmt in
            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE else { throw Failure.database(result, String(cString: sqlite3_errmsg(database))) }
        }
    }
    private func statement<T>(_ sql: String, _ values: [String] = [], _ body: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let stmt else { throw Failure.database(result, String(cString: sqlite3_errmsg(database))) }
        defer { sqlite3_finalize(stmt) }
        for (index, value) in values.enumerated() {
            let result = value.withCString { sqlite3_bind_text(stmt, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw Failure.database(result, String(cString: sqlite3_errmsg(database))) }
        }
        return try body(stmt)
    }
}
