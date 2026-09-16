import Foundation

public protocol CloudSnapshotFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func read(upToCount count: Int, from url: URL) throws -> Data?
    func writeAtomically(_ data: Data, to url: URL) throws
}

public struct LocalCloudSnapshotFileSystem: CloudSnapshotFileSystem {
    public init() {}

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func read(upToCount count: Int, from url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: count) ?? Data()
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

public struct CloudSnapshotStore: Sendable {
    public let directoryURL: URL
    public let snapshotURL: URL
    private let fileSystem: any CloudSnapshotFileSystem

    public init(
        directoryURL: URL,
        fileName: String = "subs-latest.json",
        fileSystem: any CloudSnapshotFileSystem = LocalCloudSnapshotFileSystem()
    ) {
        self.directoryURL = directoryURL
        snapshotURL = directoryURL.appending(path: fileName, directoryHint: .notDirectory)
        self.fileSystem = fileSystem
    }

    public func write(_ data: Data) throws {
        guard data.count <= SubscriptionTransfer.maxFileSize else {
            throw SubscriptionTransferError.fileTooLarge
        }
        try fileSystem.createDirectory(at: directoryURL)
        try fileSystem.writeAtomically(data, to: snapshotURL)
    }

    public func read() throws -> Data? {
        guard let data = try fileSystem.read(
            upToCount: SubscriptionTransfer.maxFileSize + 1,
            from: snapshotURL
        ) else { return nil }
        guard data.count <= SubscriptionTransfer.maxFileSize else {
            throw SubscriptionTransferError.fileTooLarge
        }
        return data
    }
}
