import Foundation
import SwiftData

public enum LocalStoreConfiguration {
    public static func make(schema: Schema, url: URL) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
    }
}
