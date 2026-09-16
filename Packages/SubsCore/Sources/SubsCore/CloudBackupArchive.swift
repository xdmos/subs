import Foundation

public struct CloudBackupArchive: Sendable {
    private let store: CloudSnapshotStore

    public init(store: CloudSnapshotStore) {
        self.store = store
    }

    public func backup(_ records: [SubscriptionRecord], at date: Date = .now) throws {
        try store.write(SubscriptionTransfer.encode(records, exportedAt: date))
    }

    public func restoreRecords() throws -> [SubscriptionRecord]? {
        guard let data = try store.read() else { return nil }
        return try SubscriptionTransfer.decode(data)
    }
}
