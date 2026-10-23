import Foundation
import Observation
import SwiftData
import AppKit

@MainActor @Observable final class ChatDraftStore {
    private(set) var state = ChatDraftState()
    private(set) var error: String?
    private(set) var writable = true
    private let container: ModelContainer?
    private var dirty = false
    private var pending: Task<Void,Never>?
    private var termination: NSObjectProtocol?
    private var visibleKeys: [UUID:String] = [:]
    private enum Failure: Error { case unsupported }
    init(container: ModelContainer?) {
        self.container = container
        do {
            if let record = try LocalRecordRepository.read("assistantDrafts", container: container) {
                let saved = try JSONDecoder().decode(ChatDraftState.self,from:record)
                guard saved.version == 1 else { throw Failure.unsupported }
                state = saved
            }
        } catch { writable = false; self.error = "Saved drafts are unavailable. Their original record is preserved; editing is disabled." }
        termination = NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.flush() } }
    }
    private static func savedDraft()->FetchDescriptor<CachedDashboard> {
        var request=FetchDescriptor<CachedDashboard>(predicate:#Predicate{$0.key == "assistantDrafts"})
        request.fetchLimit=1
        return request
    }
    func text(registration: String, widget: UUID, conversation: UUID?) -> String { state.values[ChatDraftRules.key(registration:registration,widget:widget,conversation:conversation)] ?? "" }
    func set(_ text: String, registration: String, widget: UUID, conversation: UUID?) {
        guard writable, !registration.isEmpty else { return }
        let key = ChatDraftRules.key(registration:registration,widget:widget,conversation:conversation)
        if text.isEmpty { state.values.removeValue(forKey:key) } else { state.values[key] = text }
        dirty = true; pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(500)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
    func images(registration:String,widget:UUID,conversation:UUID?)->[ChatImageAttachment] {
        state.images?[ChatDraftRules.key(registration:registration,widget:widget,conversation:conversation)] ?? []
    }
    @discardableResult func setImages(_ images:[ChatImageAttachment],registration:String,widget:UUID,conversation:UUID?)->Bool {
        guard writable,!registration.isEmpty,images.count <= 4,images.allSatisfy({$0.registration == registration}) else { return false }
        let key=ChatDraftRules.key(registration:registration,widget:widget,conversation:conversation)
        let previous=state
        if state.images == nil { state.images=[:] }
        if images.isEmpty { state.images?.removeValue(forKey:key) } else { state.images?[key]=images }
        dirty=true;flush()
        guard !dirty else { state=previous;return false };return true
    }
    func show(registration: String, widget: UUID, conversation: UUID?) { visibleKeys[widget] = ChatDraftRules.key(registration:registration,widget:widget,conversation:conversation) }
    func hide(widget: UUID) { visibleKeys.removeValue(forKey:widget) }
    func hasDraft(registration: String) -> Bool {
        visibleKeys.values.contains { $0.hasPrefix(registration+":") && (!(state.values[$0] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !(state.images?[$0] ?? []).isEmpty) }
    }
    func flush() {
        pending?.cancel(); pending = nil
        guard dirty, writable else { return }
        guard let container else { error = "Draft is kept in this session but could not be saved. Copy it before quitting."; return }
        do {
            try LocalRecordRepository(container: container).save(state, key: "assistantDrafts")
            dirty = false; error = nil
        } catch { self.error = "Draft is kept in this session but could not be saved. Copy it before quitting." }
    }
}
