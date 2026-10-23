import Foundation

enum WorkspaceTool: String, CaseIterable {
    case date, assistant, refresh, addWidget, edit, undo, appearance
    var title: String { switch self { case .date: return "Date"; case .assistant: return "Assistant"; case .refresh: return "Run heartbeat"; case .addWidget: return "Add widget"; case .edit: return "Edit layout"; case .undo: return "Undo"; case .appearance: return "Appearance" } }
}
enum ToolbarRules {
    static func visible(_ tool: WorkspaceTool, hidden: String) -> Bool { !Set(hidden.split(separator:",").map(String.init)).contains(tool.rawValue) }
    static func setting(_ tool: WorkspaceTool, visible: Bool, hidden: String) -> String {
        var values = Set(hidden.split(separator:",").map(String.init))
        if visible { values.remove(tool.rawValue) } else { values.insert(tool.rawValue) }
        return values.sorted().joined(separator:",")
    }
}
enum UndoOrder {
    static func latest(layout: Date?, completion: Date?, edit: Date?, email: Date? = nil, discovery: Date? = nil, question: Date? = nil, project: Date? = nil, memoryReview: Date? = nil, reviewQuestion:Date? = nil,activity:Date? = nil) -> String? {
        [("activity",activity),("layout",layout),("completion",completion),("edit",edit),("email",email),("discovery",discovery),("question",question),("project",project),("memoryReview",memoryReview),("reviewQuestion",reviewQuestion)].compactMap { key,date in date.map { (key,$0) } }.max { $0.1 < $1.1 }?.0
    }
}
