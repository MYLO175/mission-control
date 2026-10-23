import Foundation

/// Evaluation artifacts use the runner's private directory when provided.
/// Existing explicit developer modes retain their historical /tmp defaults.
enum EvaluationOutput {
    static func url(_ historicalPath: String) -> URL {
        guard let root = ProcessInfo.processInfo.environment["MISSIONCONTROL_TEST_ROOT"], !root.isEmpty else {
            return URL(fileURLWithPath: historicalPath)
        }
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(URL(fileURLWithPath: historicalPath).lastPathComponent)
    }
}
