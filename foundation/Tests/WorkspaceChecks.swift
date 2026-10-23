import Foundation

@main struct WorkspaceChecks {
    @MainActor static func main() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("mission-control-workspace-check-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let store=WorkspaceStore(directory:folder)
        let initial = try store.load()
        assert(initial.accounts.isEmpty)
        var state=WorkspaceState()
        state.accounts["first"] = .init(messages:[.init(role:"user",text:"First account's private question")],draft:"First draft",priorities:"First priorities")
        state.accounts["second"] = .init(messages:[.init(role:"user",text:"Second account only")],draft:"Second draft")
        try store.save(state)
        let saved=try store.load()
        assert(saved.accounts["first"]?.draft == "First draft")
        assert(saved.accounts["second"]?.messages.map(\.text) == ["Second account only"])
        assert(!ConversationRules.context(saved.accounts["second"]!.messages).description.contains("First account"))
        let messages:[ChatMessage] = [.init(role:"user",text:"Question"),.init(role:"assistant",text:"Interrupted secret fragment",completed:false),.init(role:"tool",text:"Unexpected role"),.init(role:"assistant",text:"Completed answer")]
        assert(ConversationRules.context(messages).map{$0["content"]!} == ["Question","Completed answer"])
        let long=(0..<100).map{ChatMessage(role:"user",text:String(repeating:"x",count:2000)+String($0))}
        let bounded=ConversationRules.context(long)
        assert(bounded.count <= 40 && bounded.reduce(0){$0+($1["content"]?.count ?? 0)} <= 60_000)
        let corrupt=Data("unreadable workspace".utf8)
        try corrupt.write(to:store.file)
        do {_ = try store.load();assertionFailure("Corrupt data must not become an empty workspace") } catch {}
        let preserved = try Data(contentsOf:store.file)
        assert(preserved == corrupt)
        let preview=FoundationModel(preview:true)
        assert(preview.connection == nil && preview.preview && preview.messages.count == 4)
        assert(!FileManager.default.fileExists(atPath:AppIdentity.dataDirectory.path))
        print("Workspace/account ownership, bounded context, corrupt-data preservation and isolated preview checks passed.")
    }
}
