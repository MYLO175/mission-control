import Foundation
import CoreFoundation

enum AIRequestPurpose: String, Codable, CaseIterable, Identifiable {
    case conversation, intentCheck, mailSearch, emailReview, reviewFeedback, replyDraft, brief, suggestions, learning, organisation, placement, setup, connectionCheck, diagnostic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .conversation: "PA conversation"
        case .intentCheck: "Requested action checks"
        case .mailSearch: "Email search"
        case .emailReview: "Email review"
        case .reviewFeedback: "Review feedback"
        case .replyDraft: "Reply drafts"
        case .brief: "Today's brief"
        case .suggestions: "Useful suggestions"
        case .learning: "Memory learning"
        case .organisation: "Memory organisation"
        case .placement: "Project organisation"
        case .setup: "PA setup"
        case .connectionCheck: "Connection checks"
        case .diagnostic: "Fictional evaluations"
        }
    }
}

/// Provider counts describe the observed response, never subscription allowance or price.
struct AIReportedTokens: Codable, Equatable {
    var input: Int
    var output: Int
    var total: Int
    var cachedInput: Int?
    var reasoningOutput: Int?
    var cacheWriteInput: Int? = nil

    static func parse(_ value: Any?) -> Self? {
        guard let fields = value as? [String: Any] else { return nil }
        func number(_ raw: Any?) -> Int? {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0,
                  number.doubleValue <= 1_000_000_000, number.doubleValue.rounded(.down) == number.doubleValue else { return nil }
            return number.intValue
        }
        guard let input = number(fields["input_tokens"]), let output = number(fields["output_tokens"]),
              let total = number(fields["total_tokens"]), total == input + output else { return nil }
        let cached = number((fields["input_tokens_details"] as? [String: Any])?["cached_tokens"])
        let reasoning = number((fields["output_tokens_details"] as? [String: Any])?["reasoning_tokens"])
        let written = number((fields["input_tokens_details"] as? [String: Any])?["cache_write_tokens"])
        return .init(input: input, output: output, total: total,
                     cachedInput: cached.flatMap { $0 <= input ? $0 : nil },
                     reasoningOutput: reasoning.flatMap { $0 <= output ? $0 : nil },
                     cacheWriteInput: written.flatMap { $0 <= input ? $0 : nil })
    }
    var valid: Bool {
        [input, output, total].allSatisfy { (0...1_000_000_000).contains($0) } && total == input + output &&
        cachedInput.map { (0...input).contains($0) } != false && reasoningOutput.map { (0...output).contains($0) } != false &&
        cacheWriteInput.map { (0...input).contains($0) } != false
    }
}

enum AIRequestOutcome: String, Codable { case running, completed, failed, interrupted }
struct AIUsageRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var registration: String
    var model: String
    var purpose: AIRequestPurpose
    var started: Date
    var finished: Date? = nil
    var outcome: AIRequestOutcome = .running
    var tokens: AIReportedTokens? = nil
    var httpStatus: Int? = nil
}
struct AIUsageState: Codable {
    var version = 1
    var trackingStarted = Date.now
    var truncatedBefore: Date? = nil
    var records: [AIUsageRecord] = []
}
enum AIUsageWindow: String, CaseIterable, Identifiable {
    case today, week, month
    var id: String { rawValue }
    var title: String { switch self { case .today: "Today"; case .week: "7 days"; case .month: "30 days" } }
    func start(now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: self == .today ? 0 : self == .week ? -6 : -29, to: today) ?? today
    }
}
struct AIUsageSummary {
    var calls = 0, completed = 0, failed = 0, interrupted = 0, running = 0, reportedCalls = 0
    var input = 0, output = 0, total = 0, cachedInput = 0, reasoningOutput = 0
    var cachedReportedCalls = 0, cacheWriteReportedCalls = 0, cacheWriteInput = 0
}
enum AIUsageRules {
    static let maximumRecords = 5000
    static func modelLabel(_ model: String) -> String {
        !model.isEmpty && model.count <= 128 && model.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.:/".contains($0)) } ? model : "Unavailable"
    }
    static func recovered(_ record: AIUsageRecord, now: Date) -> AIUsageRecord {
        guard record.outcome == .running else { return record }
        var result = record; result.outcome = .interrupted; result.finished = max(now, record.started); return result
    }
    static func valid(_ record: AIUsageRecord) -> Bool {
        !record.registration.isEmpty && record.registration.count <= 500 && modelLabel(record.model) == record.model &&
        record.started.timeIntervalSince1970.isFinite && record.finished.map { $0.timeIntervalSince1970.isFinite && $0 >= record.started } != false &&
        (record.outcome == .running ? record.finished == nil : record.finished != nil) && record.tokens.map(\.valid) != false &&
        record.httpStatus.map { (100...599).contains($0) } != false
    }
    static func summary(_ records: [AIUsageRecord]) -> AIUsageSummary {
        var result = AIUsageSummary()
        for record in records {
            result.calls += 1
            switch record.outcome {
            case .completed: result.completed += 1
            case .failed: result.failed += 1
            case .interrupted: result.interrupted += 1
            case .running: result.running += 1
            }
            if let usage = record.tokens {
                result.reportedCalls += 1; result.input += usage.input; result.output += usage.output; result.total += usage.total
                result.cachedInput += usage.cachedInput ?? 0; result.reasoningOutput += usage.reasoningOutput ?? 0
                if usage.cachedInput != nil { result.cachedReportedCalls += 1 }
                if let written = usage.cacheWriteInput { result.cacheWriteReportedCalls += 1; result.cacheWriteInput += written }
            }
        }
        return result
    }
}
