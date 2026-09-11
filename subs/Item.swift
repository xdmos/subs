//
//  Item.swift
//  subs
//
//  Created by Macbook M4 Pro on 11/09/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
