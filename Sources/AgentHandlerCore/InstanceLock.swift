import Foundation
import Darwin

public final class InstanceLock {
    public enum Failure: Error { case unavailable, alreadyRunning }
    private let descriptor: Int32
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Failure.unavailable }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(descriptor); throw Failure.unavailable
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(descriptor); throw Failure.alreadyRunning }
    }
    deinit { Darwin.close(descriptor) }
}
