import Foundation

@main struct ContextSourceDeltaChecks {
    static func main() throws {
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func native(_ index: Int, revision: String = "v1", changed: Date? = nil, kind: MemorySourceKind = .calendar) -> NativeLearningItem {
            .init(identity: .init(kind: kind, accountID: "fictional-provider", containerID: "fictional-container", itemID: "item-\(index)"),
                  revision: revision, label: "Fictional source", text: "A useful fictional source update number \(index).", date: now.addingTimeInterval(-600 + Double(index)), changed: changed ?? now.addingTimeInterval(-600 + Double(index)))
        }
        let nativeItems = (0..<24).map { native($0) }
        let nativeProgress = NativeLearningProgress(enabled: true, started: now.addingTimeInterval(-7_200))
        let nativeBefore = NativeLearningRules.hash(nativeProgress)
        check(NativeLearningRules.contextItems(items: nativeItems, progress: nil, processed: [:], retaining: [:], now: now).isEmpty, "No unknown native cursor can admit historical deltas")
        check(NativeLearningRules.contextItems(items: nativeItems, progress: .init(enabled: true), processed: [:], retaining: [:], now: now).isEmpty, "Unstarted native scope remains orientation-only")
        let orientedNative = NativeLearningRules.collecting(.init(enabled: true), items: nativeItems, now: now)
        check(NativeLearningRules.contextItems(items: nativeItems, progress: orientedNative, processed: [:], retaining: [:], now: now).isEmpty, "First orientation baseline is not page learning input")
        let firstNative = NativeLearningRules.contextItems(items: nativeItems, progress: nativeProgress, processed: [:], retaining: [:], now: now, limit: 8)
        check(firstNative == Array(nativeItems.prefix(8)), "Native pending selection follows deterministic source chronology")
        let processedNative = Dictionary(uniqueKeysWithValues: firstNative.map { ($0.id, $0.revision) })
        let laterNative = NativeLearningRules.contextItems(items: nativeItems, progress: nativeProgress, processed: processedNative, retaining: [:], now: now)
        check(laterNative == Array(nativeItems.dropFirst(8)), "After eight page acknowledgements the ninth and later items become visible")
        check(NativeLearningRules.batch(nativeItems, progress: nativeProgress, manual: false) == firstNative, "Working progress does not advance the source learning cursor")
        check(NativeLearningRules.contextItems(items: nativeItems.reversed(), progress: nativeProgress, processed: processedNative, retaining: [:], now: now) == laterNative, "Native input order cannot change current source selection")
        check(NativeLearningRules.contextItems(items: nativeItems, progress: nativeProgress, processed: [:], retaining: [:], now: now).count == 16, "Default pending native limit is explicit")
        check(NativeLearningRules.contextItems(items: nativeItems, progress: nativeProgress, processed: [:], retaining: [:], now: now, limit: 0).isEmpty, "Zero native limit supplies no new deltas")
        var pausedNative = nativeProgress; pausedNative.paused = true
        let oldNative = nativeItems[0], changedNative = native(0, revision: "v2", changed: now)
        let retainedOldNative = [oldNative.id: Set([oldNative.revision])]
        check(NativeLearningRules.contextItems(items: [changedNative], progress: pausedNative, processed: [:], retaining: retainedOldNative, now: now).isEmpty, "Retained native ID cannot leak changed v2 past a failed claim")
        check(NativeLearningRules.contextItems(items: [oldNative], progress: pausedNative, processed: [:], retaining: retainedOldNative, now: now) == [oldNative], "Exact unchanged native support remains valid while learning is paused")
        var baselinedNative = nativeProgress; baselinedNative.baseline[changedNative.id] = changedNative.revision
        check(NativeLearningRules.contextItems(items: [changedNative], progress: baselinedNative, processed: [:], retaining: retainedOldNative, now: now).isEmpty, "Retained old native version cannot bypass a new opt-in baseline")
        check(NativeLearningRules.contextItems(items: [changedNative], progress: nativeProgress, processed: [oldNative.id: oldNative.revision], retaining: retainedOldNative, now: now) == [changedNative], "An ordinarily eligible native v2 is independent of its processed v1")
        check(NativeLearningRules.contextItems(items: [changedNative], progress: nativeProgress, processed: [changedNative.id: changedNative.revision], retaining: retainedOldNative, now: now).isEmpty, "Exact processed native version is not offered again")
        let allNativeRetained = Dictionary(uniqueKeysWithValues: nativeItems.map { ($0.id, Set([$0.revision])) })
        check(NativeLearningRules.contextItems(items: nativeItems, progress: pausedNative, processed: [:], retaining: allNativeRetained, now: now, limit: 1).count == nativeItems.count, "Pending limit never truncates exact native page support")
        check(NativeLearningRules.contextItems(items: nativeItems, progress: nativeProgress, processed: [:], retaining: retainedOldNative, now: now, limit: 1) == [nativeItems[0], nativeItems[1]], "Retained support does not consume the pending native slot")
        check(NativeLearningRules.contextItems(items: [oldNative, oldNative], progress: nativeProgress, processed: [:], retaining: [:], now: now) == [oldNative], "Identical native duplicate rows coalesce")
        for rows in [[oldNative, changedNative], [changedNative, oldNative]] {
            check(NativeLearningRules.contextItems(items: rows, progress: pausedNative, processed: [:], retaining: retainedOldNative, now: now).isEmpty, "Conflicting native versions fail closed irrespective of source ordering")
        }
        var conflictingNative = oldNative; conflictingNative.text = "Conflicting body with the same declared revision."
        check(NativeLearningRules.contextItems(items: [oldNative, conflictingNative], progress: nativeProgress, processed: [:], retaining: retainedOldNative, now: now).isEmpty, "Conflicting same-revision native bodies are not treated as exact current support")
        var assessedNative = nativeProgress; assessedNative.assessed[oldNative.id] = oldNative.revision
        check(NativeLearningRules.contextItems(items: [oldNative], progress: assessedNative, processed: [:], retaining: [:], now: now) == [oldNative], "Learning-assessed native evidence stays available to an independently unprocessed page consumer")
        var datedMail = native(500, changed: now, kind: .mail); datedMail.date = now.addingTimeInterval(-86_400)
        check(NativeLearningRules.contextItems(items: [datedMail], progress: nativeProgress, processed: [:], retaining: [:], now: now).isEmpty, "Historical Mail newly entering coverage is baselined")
        let oldNativeSource = native(600, changed: now.addingTimeInterval(-8 * 86_400))
        check(NativeLearningRules.contextItems(items: [oldNativeSource], progress: nativeProgress, processed: [:], retaining: [:], now: now).isEmpty, "Old untracked native history is not new page input")
        var fullNative = nativeProgress; fullNative.baseline = Dictionary(uniqueKeysWithValues: (0..<6_000).map { ("old-\($0)", "v1") })
        check(NativeLearningRules.contextItems(items: [oldNative], progress: fullNative, processed: [:], retaining: [:], now: now).isEmpty, "A cursor-limit pause created during collection also blocks new page deltas")
        let nativeAfterLearning = NativeLearningRules.completing(NativeLearningRules.collecting(nativeProgress, items: nativeItems, now: now), items: firstNative, now: now)
        check(NativeLearningRules.contextItems(items: nativeItems, progress: nativeAfterLearning, processed: [:], retaining: [:], now: now, limit: 8) == firstNative, "Ordinary native learning finishing first cannot hide its new evidence from page consolidation")
        check(NativeLearningRules.contextItems(items: nativeItems, progress: nativeAfterLearning, processed: processedNative, retaining: [:], now: now) == laterNative, "Only the independent page checkpoint advances past native learning's completed first eight")
        var baselineWins = assessedNative; baselineWins.baseline[oldNative.id] = oldNative.revision
        check(NativeLearningRules.contextItems(items: [oldNative], progress: baselineWins, processed: [:], retaining: [:], now: now).isEmpty, "An explicit native baseline exclusion wins over an assessed marker")
        check(NativeLearningRules.hash(nativeProgress) == nativeBefore && !fullNative.paused, "Native context selection never mutates supplied progress")
        let otherProvider = NativeLearningItem(identity: .init(kind: .calendar, accountID: "different-fictional-provider", containerID: oldNative.identity.containerID, itemID: oldNative.identity.itemID), revision: oldNative.revision, label: oldNative.label, text: oldNative.text, date: oldNative.date, changed: oldNative.changed)
        check(otherProvider.id != oldNative.id && NativeLearningRules.contextItems(items: [otherProvider], progress: pausedNative, processed: [:], retaining: retainedOldNative, now: now).isEmpty, "Native retained identity cannot cross provider accounts")

        let chatA = "fictional-chat-a", chatB = "fictional-chat-b", chatC = "fictional-chat-c"
        let access = SourceContextLearningAccess(permitted: true, chats: Set([chatA, chatB, chatC].map(SourceContextRules.chatKey)), revision: UUID(), reviewRevision: UUID())
        func message(_ index: Int, chat: String = "fictional-chat-a", revision: String = "v1") -> SourceContextMessage {
            .init(id: SourceContextRules.messageKey(chat: chat, item: "message-\(index)"), itemID: "message-\(index)", chatID: chat,
                  chatName: "Fictional chat", sender: "Fictional person", sentByMe: false,
                  text: "The fictional project meeting is Tuesday at noon, update \(index).", date: now.addingTimeInterval(-600 + Double(index)), revision: revision)
        }
        let messages = (0..<24).map { message($0) }
        var progress = SourceContextProgress(); progress.oriented = true; progress.learningAccess = access; progress.coverage = .init()
        let sourceBefore = NativeLearningRules.hash(progress)
        check(SourceContextRules.contextItems(recent: messages, progress: nil, access: access, processed: [:], retaining: [:], now: now).isEmpty, "Unknown WhatsApp orientation cannot scan cached history")
        var unoriented = progress; unoriented.oriented = false
        check(SourceContextRules.contextItems(recent: messages, progress: unoriented, access: access, processed: [:], retaining: [:], now: now).isEmpty, "An unstarted WhatsApp scope cannot supply pending deltas")
        let firstMessages = SourceContextRules.contextItems(recent: messages, progress: progress, access: access, processed: [:], retaining: [:], now: now, limit: 8)
        check(firstMessages == Array(messages.prefix(8)), "One-chat pending deltas retain source chronology")
        let processedMessages = Dictionary(uniqueKeysWithValues: firstMessages.map { ($0.id, $0.revision) })
        let laterMessages = SourceContextRules.contextItems(recent: messages, progress: progress, access: access, processed: processedMessages, retaining: [:], now: now)
        check(laterMessages == Array(messages.dropFirst(8)), "Ninth and later WhatsApp messages progress without advancing the learning batch")
        check(SourceContextRules.batch(messages, progress: progress) == firstMessages, "Source learning cursor and original first-eight batch remain unchanged")
        check(SourceContextRules.contextItems(recent: messages.reversed(), progress: progress, access: access, processed: processedMessages, retaining: [:], now: now) == laterMessages, "WhatsApp selection is independent of cache ordering")
        check(SourceContextRules.contextItems(recent: messages, progress: progress, access: access, processed: [:], retaining: [:], now: now).count == 16, "Default pending WhatsApp limit is explicit")
        let mixed = [message(2, chat: chatA), message(1, chat: chatB), message(0, chat: chatA), message(0, chat: chatC), message(0, chat: chatB), message(1, chat: chatA)]
        let fair = SourceContextRules.contextItems(recent: mixed, progress: progress, access: access, processed: [:], retaining: [:], now: now, limit: 3)
        check(fair.map(\.chatID) == [chatA, chatB, chatC] && fair.map(\.itemID) == ["message-0", "message-0", "message-0"], "Busy chat cannot crowd out another chat's first pending message")
        var rotated = progress; rotated.coverage?.lastChat = SourceContextRules.chatKey(chatA)
        check(SourceContextRules.contextItems(recent: mixed, progress: rotated, access: access, processed: [:], retaining: [:], now: now, limit: 2).map(\.chatID) == [chatB, chatC], "Existing last-chat hint rotates fair selection deterministically")
        let oldMessage = messages[0], changedMessage = message(0, revision: "v2")
        let retainedOldMessage = [oldMessage.id: Set([oldMessage.revision])]
        var paused = progress; paused.paused = true
        check(SourceContextRules.contextItems(recent: [changedMessage], progress: paused, access: access, processed: [:], retaining: retainedOldMessage, now: now).isEmpty, "Retained message ID cannot leak changed v2 past a failed source claim")
        check(SourceContextRules.contextItems(recent: [oldMessage], progress: paused, access: access, processed: [:], retaining: retainedOldMessage, now: now) == [oldMessage], "Exact unchanged WhatsApp support remains available while learning is paused")
        var baseline = progress; baseline.coverage?.baseline[changedMessage.id] = changedMessage.revision
        check(SourceContextRules.contextItems(recent: [changedMessage], progress: baseline, access: access, processed: [:], retaining: retainedOldMessage, now: now).isEmpty, "Old retained message version cannot bypass a newly baselined version")
        check(SourceContextRules.contextItems(recent: [changedMessage], progress: progress, access: access, processed: [oldMessage.id: oldMessage.revision], retaining: retainedOldMessage, now: now) == [changedMessage], "Ordinarily eligible message v2 is independent of processed v1")
        var newEpoch = access; newEpoch.revision = UUID()
        var newReviewEpoch = access; newReviewEpoch.reviewRevision = UUID()
        var newChatSet = access; newChatSet.chats.insert(SourceContextRules.chatKey("new-fictional-chat"))
        for changedAccess in [newEpoch, newReviewEpoch, newChatSet] {
            check(SourceContextRules.contextItems(recent: messages, progress: progress, access: changedAccess, processed: [:], retaining: [:], now: now).isEmpty, "Changed access epoch or chat scope cannot admit pending historical content")
        }
        check(SourceContextRules.contextItems(recent: [oldMessage, changedMessage], progress: paused, access: access, processed: [:], retaining: retainedOldMessage, now: now).isEmpty, "Ambiguous current WhatsApp versions fail closed even when an old version was retained")
        check(SourceContextRules.contextItems(recent: [changedMessage, oldMessage], progress: progress, access: access, processed: [:], retaining: retainedOldMessage, now: now).isEmpty, "Reordered conflicting message versions cannot select a different identity winner")
        check(SourceContextRules.contextItems(recent: [oldMessage, oldMessage], progress: progress, access: access, processed: [:], retaining: [:], now: now) == [oldMessage], "Identical duplicate messages coalesce")
        var conflictingMessage = oldMessage; conflictingMessage.text = "Conflicting text with the same declared revision."
        check(SourceContextRules.contextItems(recent: [oldMessage, conflictingMessage], progress: progress, access: access, processed: [:], retaining: retainedOldMessage, now: now).isEmpty, "Conflicting same-revision message bodies fail closed")
        var denied = access; denied.permitted = false
        check(SourceContextRules.contextItems(recent: [oldMessage], progress: paused, access: denied, processed: [:], retaining: retainedOldMessage, now: now).isEmpty, "Current permission withdrawal excludes even retained support")
        var excludedChat = access; excludedChat.chats.remove(SourceContextRules.chatKey(chatA))
        check(SourceContextRules.contextItems(recent: [oldMessage], progress: paused, access: excludedChat, processed: [:], retaining: retainedOldMessage, now: now).isEmpty, "Current chat withdrawal excludes retained support")
        let allRetainedMessages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, Set([$0.revision])) })
        check(SourceContextRules.contextItems(recent: messages, progress: paused, access: access, processed: [:], retaining: allRetainedMessages, now: now, limit: 1).count == messages.count, "Pending cap never discards exact WhatsApp support for saved pages")
        check(SourceContextRules.contextItems(recent: messages, progress: progress, access: access, processed: [:], retaining: retainedOldMessage, now: now, limit: 1) == [messages[0], messages[1]], "Retained WhatsApp evidence does not consume a pending slot")
        check(SourceContextRules.contextItems(recent: messages, progress: progress, access: access, processed: [:], retaining: [:], now: now, limit: -1).isEmpty, "Negative pending cap admits no new source content")
        var legacy = progress; legacy.coverage = nil; legacy.seen[oldMessage.id] = oldMessage.revision
        check(SourceContextRules.contextItems(recent: [oldMessage], progress: legacy, access: access, processed: [:], retaining: [:], now: now).isEmpty, "Legacy seen cursor migrates as baseline, not new page input")
        var alreadySeen = progress; alreadySeen.seen[oldMessage.id] = oldMessage.revision; alreadySeen.coverage?.assessedDates[oldMessage.id] = oldMessage.date
        check(SourceContextRules.contextItems(recent: [oldMessage], progress: alreadySeen, access: access, processed: [:], retaining: [:], now: now) == [oldMessage], "Learning-seen evidence remains available to independently unprocessed page context")
        let sourceAfterLearning = SourceContextRules.completing(SourceContextRules.collecting(progress, recent: messages, now: now), batch: firstMessages, now: now)
        check(SourceContextRules.contextItems(recent: messages, progress: sourceAfterLearning, access: access, processed: [:], retaining: [:], now: now, limit: 8) == firstMessages, "Ordinary WhatsApp learning finishing first cannot hide its evidence from page consolidation")
        check(SourceContextRules.contextItems(recent: messages, progress: sourceAfterLearning, access: access, processed: processedMessages, retaining: [:], now: now) == laterMessages, "The page checkpoint independently advances beyond already learned WhatsApp messages")
        var sourceBaselineWins = alreadySeen; sourceBaselineWins.coverage?.baseline[oldMessage.id] = oldMessage.revision
        check(SourceContextRules.contextItems(recent: [oldMessage], progress: sourceBaselineWins, access: access, processed: [:], retaining: [:], now: now).isEmpty, "Baseline exclusion remains authoritative even with a learning-seen marker")
        check(NativeLearningRules.hash(progress) == sourceBefore && paused.paused && baseline.coverage?.baseline[changedMessage.id] == changedMessage.revision, "WhatsApp selectors do not mutate supplied cursor/baseline/claim state")

        // Exercise the cache projection before the pure delta selector: exact retained
        // support survives both the recent-time boundary and the 2,000-row window.
        func cached(_ id:String,chat:String = "fictional-chat-a",date:Date,text:String = "Fictional project context retained by a saved page.")->WhatsAppReadMessage {
            .init(id:id,chat:chat,sender:"Fictional person",text:text,sentByMe:false,time:date.timeIntervalSince1970*1000)
        }
        let chats=[WhatsAppChat(id:chatA,name:"Fictional chat A",group:false),WhatsAppChat(id:chatB,name:"Fictional chat B",group:false)]
        let rawOld=cached("retained-before-window",date:now.addingTimeInterval(-49*3600))
        let oldKey=SourceContextRules.messageKey(chat:rawOld.chat,item:rawOld.id)
        let retainingOld=[oldKey:Set([SourceContextRules.revision(rawOld)])]
        check(SourceContextRules.recent([rawOld],chats:chats,allowed:[chatA],now:now,limit:2000).isEmpty,"An unreferenced cached message older than 48 hours stays outside fresh context")
        let retainedProjection=SourceContextRules.recent([rawOld],chats:chats,allowed:[chatA],now:now,limit:2000,retaining:retainingOld)
        check(retainedProjection.count == 1 && retainedProjection[0].id == oldKey && retainedProjection[0].revision == SourceContextRules.revision(rawOld),"Exact unchanged cached support survives the 48-hour boundary")
        check(SourceContextRules.contextItems(recent:retainedProjection,progress:paused,access:access,processed:[:],retaining:retainingOld,now:now) == retainedProjection,"Older retained support remains usable without resuming a failed learning claim")
        check(SourceContextRules.contextItems(recent:retainedProjection,progress:progress,access:access,processed:[:],retaining:[:],now:now).isEmpty,"An older retained projection cannot be repurposed as an untracked fresh delta")
        let changedOld=cached(rawOld.id,date:Date(timeIntervalSince1970:rawOld.time/1000),text:"The same old message now has different source text.")
        check(SourceContextRules.recent([changedOld],chats:chats,allowed:[chatA],now:now,limit:2000,retaining:retainingOld).isEmpty,"An edited old message is neither exact retained support nor new recent history")
        var changedOldProjection=retainedProjection[0];changedOldProjection.text=changedOld.text;changedOldProjection.revision=SourceContextRules.revision(changedOld)
        var oldSeen=progress;oldSeen.seen[oldKey]=changedOldProjection.revision;oldSeen.coverage?.assessedDates[oldKey]=changedOldProjection.date
        check(SourceContextRules.contextItems(recent:[changedOldProjection],progress:oldSeen,access:access,processed:[:],retaining:retainingOld,now:now).isEmpty,"A learning-seen marker cannot admit a changed old retained ID past the fresh-date guard")
        check(SourceContextRules.contextItems(recent:retainedProjection,progress:progress,access:denied,processed:[:],retaining:retainingOld,now:now).isEmpty,"Permission withdrawal excludes old retained support")
        check(SourceContextRules.contextItems(recent:retainedProjection,progress:progress,access:excludedChat,processed:[:],retaining:retainingOld,now:now).isEmpty,"Removed chat access excludes old retained support")
        check(SourceContextRules.recent([rawOld],chats:chats,allowed:[chatB],now:now,retaining:retainingOld).isEmpty,"The cache projection also filters withdrawn chats before retention")
        let sameIDOtherChat=cached(rawOld.id,chat:chatB,date:Date(timeIntervalSince1970:rawOld.time/1000))
        check(SourceContextRules.recent([sameIDOtherChat],chats:chats,allowed:[chatA,chatB],now:now,retaining:retainingOld).isEmpty,"Equal raw message IDs in different chats cannot substitute for retained evidence")
        for duplicateRows in [[rawOld,changedOld],[changedOld,rawOld]] {
            check(SourceContextRules.recent(duplicateRows,chats:chats,allowed:[chatA],now:now,retaining:retainingOld).isEmpty,"Conflicting cached versions fail closed before age selection, regardless of row order")
        }
        check(SourceContextRules.recent([rawOld,rawOld],chats:chats,allowed:[chatA],now:now,retaining:retainingOld) == retainedProjection,"Identical cached retained duplicates coalesce")
        let freshDuplicate=cached(rawOld.id,date:now.addingTimeInterval(-30),text:"Conflicting newly timestamped copy of an old retained identity.")
        check(SourceContextRules.recent([rawOld,freshDuplicate],chats:chats,allowed:[chatA],now:now,retaining:retainingOld).isEmpty,"A conflicting fresh duplicate cannot hide an older conflicting row outside 48 hours")
        let rawWindow=(0..<2001).map{cached("window-\($0)",date:now.addingTimeInterval(-120-Double($0)))}
        let outside=rawWindow.last!,outsideKey=SourceContextRules.messageKey(chat:outside.chat,item:outside.id)
        let retainingOutside=[outsideKey:Set([SourceContextRules.revision(outside)])]
        let boundedWindow=SourceContextRules.recent(rawWindow,chats:chats,allowed:[chatA],now:now,limit:2000)
        check(boundedWindow.count == 2000 && !boundedWindow.contains{$0.id == outsideKey},"The ordinary fresh cache projection retains its 2,000-message cap")
        let widenedSupport=SourceContextRules.recent(rawWindow,chats:chats,allowed:[chatA],now:now,limit:2000,retaining:retainingOutside)
        check(widenedSupport.count == 2001 && Set(widenedSupport.map(\.id)).count == 2001 && widenedSupport.contains{$0.id == outsideKey},"Exact page support beyond capacity is added once without evicting fresh allocation")
        check(SourceContextRules.recent(rawWindow.reversed(),chats:chats,allowed:[chatA],now:now,limit:2000,retaining:retainingOutside) == widenedSupport,"Retained capacity support does not depend on cache row ordering")
        check(SourceContextRules.contextItems(recent:widenedSupport,progress:progress,access:access,processed:[:],retaining:retainingOutside,now:now,limit:0).map(\.id) == [outsideKey],"Retained capacity support survives independently of the pending-delta limit")
        let firstRaw=rawWindow[0],retainingInside=[SourceContextRules.messageKey(chat:firstRaw.chat,item:firstRaw.id):Set([SourceContextRules.revision(firstRaw)])]
        check(SourceContextRules.recent(rawWindow,chats:chats,allowed:[chatA],now:now,limit:2000,retaining:retainingInside) == boundedWindow,"Retained support already inside the window is not duplicated")
        let conflictingOutside=cached(outside.id,date:Date(timeIntervalSince1970:outside.time/1000),text:"Conflicting cache body outside the fresh capacity limit.")
        check(!SourceContextRules.recent(rawWindow+[conflictingOutside],chats:chats,allowed:[chatA],now:now,limit:2000,retaining:retainingOutside).contains{$0.id == outsideKey},"Conflicting versions beyond the window cannot establish retained current support")
        let future=cached("future",date:now.addingTimeInterval(60)),futureKey=SourceContextRules.messageKey(chat:chatA,item:"future")
        check(SourceContextRules.recent([future],chats:chats,allowed:[chatA],now:now,retaining:[futureKey:Set([SourceContextRules.revision(future)])]).isEmpty,"Retained IDs do not bypass the future-timestamp guard")

        let linkedIdentity = "fictional-whatsapp-identity", registration = "fictional-chatgpt-account"
        let output: [String: Any] = ["facts": [["messageID": oldMessage.id, "text": "A fictional message reports a meeting.", "quote": oldMessage.text, "kind": "context", "areas": ["studies"]]]]
        let decoded = SourceContextRules.decode(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self), messages: [oldMessage], registration: registration, linkedIdentity: linkedIdentity, now: now)!.first!
        let canonicalIdentity = MemorySourceIdentity(kind: .whatsapp, accountID: linkedIdentity, containerID: oldMessage.chatID, itemID: oldMessage.itemID, linkedIdentity: linkedIdentity)
        check(decoded.registration == registration && decoded.source?.identity == canonicalIdentity, "Canonical source evidence binds the WhatsApp linked identity, separately from ChatGPT ownership")
        var wrongEvidence = decoded.source!; wrongEvidence.identity.accountID = registration
        check(PAMemory.suppressionKey(decoded.source!) != PAMemory.suppressionKey(wrongEvidence), "Using ChatGPT registration for source identity cannot match a forgotten WhatsApp evidence key")
        var sameEvidence = decoded.source!; sameEvidence.identity = canonicalIdentity
        check(PAMemory.suppressionKey(decoded.source!) == PAMemory.suppressionKey(sameEvidence), "Canonical source identity reproduces exact Forget suppression")
        print("PASS: \(count) context-source delta checks; actual pure rules and fictional inputs only")
    }
}
