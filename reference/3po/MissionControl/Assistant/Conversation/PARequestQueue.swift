import Foundation
import SwiftData
import Observation

enum PAQueuedState: String, Codable { case waiting, running, interrupted, needsAnswer, completed }
struct PAQueuedRequest: Identifiable, Codable, Equatable {
    var id = UUID()
    var registration: String
    var topicID: UUID?
    var prompt: String
    var created = Date.now
    var state: PAQueuedState = .waiting
    var result: String? = nil
    var finished: Date? = nil
    var focusAreas:[LifeArea]? = nil
    var images:[ChatImageAttachment]? = nil
}
enum PAQueueRules {
    static func recover(_ values: [PAQueuedRequest]) -> [PAQueuedRequest] {
        values.map { value in var item=value; if item.state == .running { item.state = .interrupted }; return item }
    }
    static func handoffs(_ values:[PAQueuedRequest],registration:String)->[PAQueuedRequest] { values.filter { $0.registration == registration && $0.state != .completed } }
    static func next(_ values:[PAQueuedRequest],registration:String) -> PAQueuedRequest? {
        values.first { $0.registration == registration && $0.state == .waiting }
    }
}
@MainActor @Observable final class PARequestQueue {
    private(set) var items:[PAQueuedRequest] = []
    private(set) var error:String?
    private let container:ModelContainer?
    private var writable=true
    init(container:ModelContainer?) {
        self.container=container
        do {
            if let record = try LocalRecordRepository.read("paRequestQueue", container: container) {
                let values=try JSONDecoder().decode([PAQueuedRequest].self,from: record)
                guard Set(values.map(\.id)).count == values.count else { throw CocoaError(.fileReadCorruptFile) }
                items=PAQueueRules.recover(values)
            }
        } catch { writable=false; self.error="Saved requests could not be read; the original record is preserved." }
    }
    @discardableResult func add(registration:String,topicID:UUID?,prompt:String,focusAreas:[LifeArea]? = nil,images:[ChatImageAttachment] = [])->Bool {
        guard !registration.isEmpty, (!prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !images.isEmpty),images.count <= 4,images.allSatisfy({$0.registration == registration}), ConversationRules.acceptsPrompt(prompt) else { error="The queued message or its images are invalid or too large. Your draft is kept."; return false }
        return change { values in
            values.append(.init(registration:registration,topicID:topicID,prompt:prompt,focusAreas:focusAreas,images:images.isEmpty ? nil : images))
        }
    }
    @discardableResult func mark(_ id:UUID,_ state:PAQueuedState)->Bool { change { values in if let i=values.firstIndex(where:{$0.id == id}) { values[i].state=state } } }
    @discardableResult func finish(_ id:UUID,result:String,needsAnswer:Bool)->Bool {
        change { values in if let i=values.firstIndex(where:{$0.id == id}) { values[i].state=needsAnswer ? .needsAnswer : .completed; values[i].result=String(result.prefix(6000)); values[i].finished = .now } }
    }
    @discardableResult func remove(_ id:UUID)->Bool { change { $0.removeAll { $0.id == id } } }
    private func change(_ action:(inout [PAQueuedRequest])->Void)->Bool {
        guard writable,let container else { error="Request storage is unavailable. Your draft is kept."; return false }
        var revised=items; action(&revised)
        do {
            try LocalRecordRepository(container: container).save(revised, key: "paRequestQueue")
            items=revised; error=nil; return true
        } catch { self.error="The request queue could not be saved."; return false }
    }
}
