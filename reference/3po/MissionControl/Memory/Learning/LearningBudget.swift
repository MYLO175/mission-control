import Foundation
import Observation
import SwiftData

struct LearningBudgetProgress:Codable {
    var day=""
    var attempts=0
    var lastAttempt:Date?
    var lastServed: [String: Date]? = nil
}
enum LearningBudgetRules {
    static func allowed(_ progress:LearningBudgetProgress,now:Date)->Bool {
        (progress.day != BriefingRules.day(now) || progress.attempts < 4) && now.timeIntervalSince(progress.lastAttempt ?? .distantPast) >= 1800
    }
}
/// Shared across conversation learning, notebook organisation and optional source learning.
/// Foreground requests, briefs and proactive suggestions keep their own existing bounds.
@MainActor @Observable final class LearningBudget {
    private var accounts:[String:LearningBudgetProgress]=[:]
    private let container:ModelContainer?
    private let repository:LocalRecordRepository?
    private var readable=true
    private(set) var revision = UUID()
    func receipts(_ registration: String) -> [LearningLane: Date] {
        Dictionary(uniqueKeysWithValues: (accounts[registration]?.lastServed ?? [:]).compactMap { key, date in
            LearningLane(rawValue: key).map { ($0, date) }
        })
    }
    init(container:ModelContainer?,repository:LocalRecordRepository? = nil) {
        self.container=container
        self.repository=repository ?? container.map { LocalRecordRepository(container:$0) }
        do {
            if let saved = try self.repository?.read("paCombinedLearningBudget") { accounts=try JSONDecoder().decode([String:LearningBudgetProgress].self,from: saved) }
        } catch { readable=false }
    }
    func claim(_ registration:String,manual:Bool,now:Date = .now,lane:LearningLane? = nil)->Bool {
        guard readable,!registration.isEmpty else { return false }
        if manual { return true }
        let prior=accounts
        var value=accounts[registration] ?? .init()
        guard LearningBudgetRules.allowed(value,now:now),container != nil,let repository else { return false }
        if value.day != BriefingRules.day(now) { value.day=BriefingRules.day(now);value.attempts=0 }
        value.attempts += 1;value.lastAttempt=now;accounts[registration]=value
        if let lane {
            if value.lastServed == nil { value.lastServed = [:] }
            value.lastServed?[lane.rawValue] = now
            accounts[registration] = value
        }
        do {
            try repository.write(["paCombinedLearningBudget": JSONEncoder().encode(accounts)], now: now)
            revision = UUID(); return true
        } catch { accounts=prior;return false }
    }
}
