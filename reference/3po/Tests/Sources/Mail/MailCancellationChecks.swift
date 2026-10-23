import Foundation

/// Real helper-process cancellation, using a source-free disposable script.
@main struct MailCancellationChecks {
    static func main() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("mail-cancellation-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let script=folder.appendingPathComponent("Fixture.js")
        try """
        ObjC.import('Foundation');
        function run(argv) {
            const input=JSON.parse(argv[0]);
            if(input.operation==='batch') {$.NSThread.sleepForTimeInterval(8);}
            return JSON.stringify({accounts:[],errors:[]});
        }
        """.write(to:script,atomically:true,encoding:.utf8)
        let service=MailService(scriptURL:script)
        let now=Date.now,window=MailWindowProgress(id:"fixture",accountID:"fixture",start:now.addingTimeInterval(-86400),end:now)
        for _ in 0..<3 {
            let began=ContinuousClock.now
            let task=Task {try await service.batch(accountID:"fixture",window:window)}
            try await Task.sleep(for:.milliseconds(250))
            task.cancel()
            do {_ = try await task.value;fatalError("Cancelled read returned a result")}
            catch is CancellationError {} // Must not masquerade as a timeout/account error.
            guard began.duration(to:.now) < .seconds(3) else {fatalError("Cancelled helper kept the Mail actor occupied")}
            let discovery=try await service.discoverAccounts()
            guard discovery.accounts.isEmpty,discovery.errors.isEmpty else {fatalError("Next source read could not continue")}
        }
        let timeoutService=MailService(scriptURL:script,timeout:0.3)
        do {_ = try await timeoutService.batch(accountID:"fixture",window:window);fatalError("Unresponsive helper did not time out")}
        catch MailServiceError.timedOut {}
        let discovery=try await timeoutService.discoverAccounts()
        guard discovery.errors.isEmpty else {fatalError("Timeout prevented later source recovery")}
        print("PASS Mail helper: repeated running cancellation releases serial actor, typed cancellation differs from timeout, later discovery recovers. Source-free; no Mail access, AI or cache mutation.")
    }
}
