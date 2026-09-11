//
//  Subscription.swift
//  subs
//

import Foundation
import SwiftData

@Model
final class Subscription {
    @Attribute(.unique) var id: UUID
    var name: String
    var startDate: Date

    init(name: String, startDate: Date, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.startDate = startDate
    }
}
