import Foundation

/// A local display preference, never a conversation ID or an instruction template.
enum PAIdentity {
    static let defaultName = "Your PA"
    static func validated(_ value:String)->String? {
        guard !value.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else { return nil }
        let name=value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.count <= 40 else { return nil }
        return name
    }
    static func name(_ value:String?)->String { value.flatMap(validated) ?? defaultName }
    static func placeholder(_ value:String)->String { value == defaultName ? "Message your PA" : "Message " + name(value) }
    static func context(_ value:String)->String { String(data:(try? JSONEncoder().encode(name(value))) ?? Data(),encoding:.utf8) ?? "\"Your PA\"" }
}
