import Foundation
import SwiftData

@main struct Checks {
    @MainActor static func main() throws {
        let tokens = AIReportedTokens.parse(["input_tokens":100,"output_tokens":20,"total_tokens":120,"input_tokens_details":["cached_tokens":40],"output_tokens_details":["reasoning_tokens":12]])!
        precondition(tokens.valid && tokens.total == 120)
        let cacheWrites = AIReportedTokens.parse(["input_tokens":100,"output_tokens":20,"total_tokens":120,"input_tokens_details":["cached_tokens":0,"cache_write_tokens":80]])!
        precondition(cacheWrites.valid && cacheWrites.cachedInput == 0 && cacheWrites.cacheWriteInput == 80)
        let noCacheReport = AIReportedTokens.parse(["input_tokens":100,"output_tokens":20,"total_tokens":120])!
        precondition(noCacheReport.cachedInput == nil && noCacheReport.cacheWriteInput == nil)
        precondition(AIReportedTokens.parse(["input_tokens":100,"output_tokens":20,"total_tokens":120,"input_tokens_details":["cache_write_tokens":101]])?.cacheWriteInput == nil)
        let oldTokenJSON = Data("{\"input\":100,\"output\":20,\"total\":120,\"cachedInput\":40}".utf8)
        let restoredOldTokens = try JSONDecoder().decode(AIReportedTokens.self, from: oldTokenJSON)
        precondition(restoredOldTokens.cacheWriteInput == nil)
        let invalidCounts: [Any] = [true, -1, 1.5, "100", Double.infinity, 1_000_000_001]
        for invalid in invalidCounts {
            precondition(AIReportedTokens.parse(["input_tokens":invalid,"output_tokens":20,"total_tokens":120]) == nil)
        }
        precondition(AIReportedTokens.parse(["input_tokens":100,"output_tokens":20,"total_tokens":121]) == nil)
        precondition(AIReportedTokens.parse(["input_tokens":0,"output_tokens":0,"total_tokens":0])?.total == 0)
        precondition(AIReportedTokens.parse(["input_tokens":100,"output_tokens":20,"total_tokens":120,"input_tokens_details":["cached_tokens":101]])?.cachedInput == nil)
        let now = Date(timeIntervalSince1970:2_000_000_000)
        let container = try ModelContainer(for:CachedDashboard.self, configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store = AIUsageStore(container:container,now:now)
        let a = store.begin(registration:"account-a",model:"gpt-test",purpose:.conversation,now:now)!
        let b = store.begin(registration:"account-b",model:"gpt-test",purpose:.learning,now:now)!
        store.finish(a,outcome:.completed,tokens:tokens,now:now)
        store.finish(a,outcome:.failed,now:now)
        precondition(store.records(registration:"account-a",window:.today,now:now).count == 1)
        let summary = AIUsageRules.summary(store.records(registration:"account-a",window:.today,now:now))
        precondition(summary.calls == 1 && summary.completed == 1 && summary.total == 120 && summary.cachedInput == 40 && summary.reasoningOutput == 12)
        precondition(summary.cachedReportedCalls == 1 && summary.cacheWriteReportedCalls == 0)
        var unknownUsage = AIUsageRecord(registration:"account-a",model:"gpt-test",purpose:.conversation,started:now)
        unknownUsage.tokens = noCacheReport
        let unknownSummary = AIUsageRules.summary([unknownUsage])
        precondition(unknownSummary.reportedCalls == 1 && unknownSummary.cachedReportedCalls == 0 && unknownSummary.cacheWriteReportedCalls == 0)
        let recovered = AIUsageStore(container:container,now:now)
        precondition(recovered.state.records.first(where:{$0.id == b})?.outcome == .interrupted)
        precondition(recovered.state.records.first(where:{$0.id == a})?.outcome == .completed)
        let failure = recovered.begin(registration:"account-a",model:"Bearer secret",purpose:.brief,now:now)!
        recovered.finish(failure,outcome:.failed,httpStatus:429,now:now)
        precondition(recovered.state.records.first(where:{$0.id == failure})?.model == "Unavailable")
        let json = String(decoding:try JSONEncoder().encode(recovered.state),as:UTF8.self)
        precondition(!json.contains("Bearer secret") && !json.contains("prompt") && !json.contains("response"))
        let retained = recovered.begin(registration:"account-a",model:"gpt-test",purpose:.suggestions,now:now.addingTimeInterval(31*86400))!
        precondition(recovered.state.records.map(\.id) == [retained] && recovered.state.truncatedBefore != nil)
        var london = Calendar(identifier:.gregorian);london.timeZone = TimeZone(identifier:"Europe/London")!
        let formatter = ISO8601DateFormatter()
        let before = formatter.date(from:"2026-10-05T22:59:00Z")!, after = formatter.date(from:"2026-10-05T23:01:00Z")!
        precondition(before < AIUsageWindow.today.start(now:after,calendar:london))
        let corruptContainer = try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let original = Data("not json".utf8)
        corruptContainer.mainContext.insert(CachedDashboard(key:"paAIUsage",data:original));try corruptContainer.mainContext.save()
        let corrupt = AIUsageStore(container:corruptContainer)
        precondition(corrupt.error != nil && corrupt.begin(registration:"account",model:"test",purpose:.conversation) == nil)
        let preserved = try corruptContainer.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first!.data
        precondition(preserved == original)
        print("PASS: provider counts, unknown/invalid metadata, account isolation, terminal outcomes, interrupted recovery, privacy, retention, local-day boundaries and corrupt-store preservation")
    }
}
