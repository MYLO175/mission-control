import Foundation
import SwiftData

@Model final class CachedDashboard {
    @Attribute(.unique) var key: String
    var data: Data
    var updated: Date
    init(key: String, data: Data, updated: Date = .now) { self.key = key; self.data = data; self.updated = updated }
}
