//
//  Subscription.swift
//  subs
//

import Foundation
import SwiftData

@Model
public final class Subscription {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var startDate: Date

    public init(name: String, startDate: Date, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.startDate = startDate
    }
}
