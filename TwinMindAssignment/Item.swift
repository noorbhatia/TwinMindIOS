//
//  Item.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
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
