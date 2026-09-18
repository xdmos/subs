import Foundation
import SwiftData
import Testing
@testable import SubsCore

struct LocalStoreConfigurationTests {
    @Test func localStoreExplicitlyDisablesCloudKit() {
        let schema = Schema([Subscription.self])
        let url = URL(filePath: "/tmp/subs-local-only.store")

        let configuration = LocalStoreConfiguration.make(schema: schema, url: url)
        let expected = ModelConfiguration(
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )

        #expect(configuration == expected)
    }
}
