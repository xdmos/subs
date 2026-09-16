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
        if FileManager.default.isUbiquitousItem(at: url) {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        }

        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? handle.close() }
                return try handle.read(upToCount: count) ?? Data()
            }
        }
        if let coordinationError { throw coordinationError }
        return try result?.get()
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) {
            do {
                try data.write(to: $0, options: [.atomic, .completeFileProtection])
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
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
