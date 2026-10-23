import Foundation

enum LifeFocusRules {
    static func normalised(_ raw:[String])->[LifeArea] { LifeArea.allCases.filter { raw.contains($0.rawValue) } }
    static func label(_ areas:[LifeArea])->String { areas.isEmpty ? "All areas" : areas.count == 1 ? areas[0].title : "Focus · \(areas.count)" }
}
