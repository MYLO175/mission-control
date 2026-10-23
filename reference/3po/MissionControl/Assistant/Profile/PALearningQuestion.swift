import Foundation

struct LearningQuestionDraft: Codable, Equatable {
    var turnID: String
    var text: String
    var evidence: String
}
struct MemoryLearningAssessment {
    var memories: [LearnedMemory]
    var question: LearningQuestionDraft?
}
struct PALearningQuestion: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var registration: String
    var conversationID: UUID?
    var turnID: String
    var text: String
    var evidence: String
    var created: Date
    var dismissed = false
    var answered:Bool? = nil
    var deliveryID: String { "learn-question:" + id }
}
enum LearningQuestionRules {
    static func allowed(progress: MemoryLearningProgress, records: [PALearningQuestion], registration: String, day: String) -> Bool {
        progress.lastQuestionDay != day && !records.contains { $0.registration == registration && BriefingRules.day($0.created) == day }
    }
    static func record(_ draft: LearningQuestionDraft, turns: [MemoryLearningTurn], prior: [PALearningQuestion], registration: String, now: Date) -> PALearningQuestion? {
        guard let origin = turns.first(where:{ $0.id == draft.turnID }), !prior.contains(where:{ $0.registration == registration && $0.turnID == draft.turnID }) else { return nil }
        return PALearningQuestion(registration:registration,conversationID:origin.conversationID,turnID:draft.turnID,text:draft.text,evidence:draft.evidence,created:now)
    }
}
