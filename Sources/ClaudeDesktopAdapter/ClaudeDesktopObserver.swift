import Foundation
import CryptoKit
import AgentHandlerCore

/// Observes only locally written audit files. No command, hook, response transport or credential access.
public actor ClaudeDesktopObserver {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")
    }
    private let root: URL
    private let installation: String
    private let now: @Sendable () -> Date
    private var source: String?
    private var began: TimeInterval = 0
    private var cursors: [AuditLocation: ClaudeAuditCursor] = [:]
    private var requiresBaseline: Set<AuditLocation> = []
    private var selected: Set<AuditLocation> = []
    private var store = ActivityStore()
    private var epochs: [RequestScope: UUID] = [:]
    private var revision: Int64 = 0
    private var message = "Claude local audits not started"

    public init(root: URL = ClaudeDesktopObserver.defaultRoot, now: @escaping @Sendable () -> Date = Date.init) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.now = now
        installation = "claude-local-audit:" + SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    public func activity() -> [ActivityView] { store.views }
    public func health() -> String { message }
    public func stop() {
        for (scope, epoch) in epochs { store.invalidate(scope: scope, epoch: epoch) }
        source = nil; cursors = [:]; requiresBaseline = []; selected = []; epochs = [:]
        message = "Claude local observation unavailable"
    }
    private func scope(_ location: AuditLocation) -> RequestScope {
        .init(installation: installation, conversation: location.key)
    }
    private func invalidate(_ location: AuditLocation) {
        let scope = scope(location)
        if let epoch = epochs[scope] { store.invalidate(scope: scope, epoch: epoch) }
    }
    private func readFailed(_ location: AuditLocation) {
        cursors.removeValue(forKey: location)
        requiresBaseline.insert(location)
        invalidate(location)
    }
    public func poll(sourceInstance: String?) {
        guard let sourceInstance else { stop(); message = "Claude not running · local audit observation only"; return }
        do {
            let locations = try ClaudeAuditFiles.discover(root: root)
            if source != sourceInstance {
                stop(); source = sourceInstance; began = now().timeIntervalSince1970
                requiresBaseline = Set(locations)
                for location in locations {
                    if let file = try? ReadOnlyAuditFile(root: root, components: location.audit) {
                        cursors[location] = try? ClaudeAuditCursor(file: file, atEnd: true)
                    }
                }
                message = "Claude local audits · \(cursors.count) baselined · awaiting new turns"
                return
            }
            let present = Set(locations)
            requiresBaseline.formIntersection(present)
            for location in cursors.keys where !present.contains(location) {
                cursors.removeValue(forKey: location); selected.remove(location)
                store.remove(scope: scope(location)); epochs.removeValue(forKey: scope(location))
            }
            var infos: [AuditLocation: ReadOnlyAuditFile.Info] = [:]
            var changed: Set<AuditLocation> = []
            var faults = 0
            for location in locations {
                do {
                    let file = try ReadOnlyAuditFile(root: root, components: location.audit), info = try file.info()
                    infos[location] = info
                    if cursors[location] == nil {
                        cursors[location] = try ClaudeAuditCursor(file: file,
                            atEnd: requiresBaseline.contains(location) || info.birth < began || info.birth <= 0)
                    }
                    if let cursor = cursors[location], cursor.info != info || cursor.offset < info.size { changed.insert(location) }
                } catch { faults += 1; readFailed(location) }
            }
            let urgent = selected.filter { location in
                store.views.contains { $0.id == scope(location) && [.running, .needsInput].contains($0.status) }
            }.sorted { $0.key < $1.key }
            let additions = changed.sorted {
                let a = infos[$0]!, b = infos[$1]!
                return (a.modifiedSeconds, a.modifiedNanoseconds, $0.key) > (b.modifiedSeconds, b.modifiedNanoseconds, $1.key)
            }
            var wanted: [AuditLocation] = []
            for location in urgent + additions + selected.sorted(by: { $0.key < $1.key })
                where !wanted.contains(location) && wanted.count < 16 { wanted.append(location) }
            let following = Set(wanted)
            let limited = changed.subtracting(following)
            for location in selected.subtracting(following).union(limited) {
                store.remove(scope: scope(location)); epochs.removeValue(forKey: scope(location))
                do {
                    let file = try ReadOnlyAuditFile(root: root, components: location.audit)
                    cursors[location] = try ClaudeAuditCursor(file: file, atEnd: true)
                } catch { faults += 1; readFailed(location) }
            }
            selected = following
            for location in wanted {
                do {
                    guard var cursor = cursors[location] else { continue }
                    let metadata = try ReadOnlyAuditFile(root: root, components: location.metadata), metaInfo = try metadata.info()
                    if cursor.metadataInfo != metaInfo {
                        guard metaInfo.size <= 512 * 1024 else { throw ClaudeAuditFiles.Failure.capacity }
                        cursor.eligible = try ClaudeAuditFiles.eligible(metadata.read(offset: 0, count: Int(metaInfo.size)), session: location.session)
                        cursor.metadataInfo = metaInfo
                    }
                    guard cursor.eligible == true else {
                        store.remove(scope: scope(location)); epochs.removeValue(forKey: scope(location)); selected.remove(location)
                        let file = try ReadOnlyAuditFile(root: root, components: location.audit)
                        cursors[location] = try ClaudeAuditCursor(file: file, atEnd: true)
                        continue
                    }
                    let file = try ReadOnlyAuditFile(root: root, components: location.audit)
                    try cursor.read(file); cursors[location] = cursor
                    requiresBaseline.remove(location)
                    let scope = scope(location)
                    if cursor.caughtUp, let value = cursor.state.observation {
                        let epoch = epochs[scope] ?? store.begin(scope: scope)
                        epochs[scope] = epoch; revision += 1
                        store.observe(.init(scope: scope, epoch: epoch, revision: revision,
                            turnID: value.turnID, phase: value.phase, attention: value.attention))
                    } else { invalidate(location) }
                } catch { faults += 1; readFailed(location) }
            }
            // Records from a previous process remain unknown until fresh sources replace them.
            for view in store.views where store.views.count > 16 && !selected.contains(where: { scope($0) == view.id }) {
                store.remove(scope: view.id); epochs.removeValue(forKey: view.id)
            }
            let views = store.views
            message = "Claude local audits · \(views.filter(\.isCurrent).count) current · \(views.filter { $0.status == .needsInput }.count) need input · read-only"
            if faults > 0 { message += " · \(faults) unavailable sources" }
            if !limited.isEmpty { message += " · capacity exceeded" }
        } catch {
            for (scope, epoch) in epochs { store.invalidate(scope: scope, epoch: epoch) }
            // A discovery gap discards active correlation; the next poll must baseline again.
            source = nil; cursors = [:]; requiresBaseline = []; selected = []
            message = "Claude local audits unavailable or incompatible"
        }
    }
}
