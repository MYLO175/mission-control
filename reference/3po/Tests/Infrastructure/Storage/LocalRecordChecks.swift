import Foundation
import SwiftData

private struct KnownNumericDocument: Codable {
    var saved: Date
    var measurement: Double
    var text: String
}
private struct OpaqueNumericRow: Codable { var id: UUID; var title: String }
private struct OpaqueNumericRows: Codable { var rows: [OpaqueNumericRow] }

@main struct LocalRecordChecks {
    @MainActor static func main() throws {
        if let index=CommandLine.arguments.firstIndex(of:"--lease-probe"),CommandLine.arguments.indices.contains(index+1) {
            do { let lease=try LocalRecordFileLease(url:URL(fileURLWithPath:CommandLine.arguments[index+1]));withExtendedLifetime(lease) {};exit(0) }
            catch {exit(23)}
        }
        enum Injected: Error { case failed }
        func check(_ value: Bool, _ message: String = "Storage contract failed") { precondition(value, message) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("3po-storage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fictional.store")
        func open() throws -> ModelContainer {
            try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        }
        let container = try open(), records = LocalRecordRepository(container: container)
        let original = Data("original receipt".utf8), revised = Data("pending receipt".utf8)
        try records.write(["action": original, "sources": original, "cursor": original, "legacy": Data([0,1,2])])
        let unrelated = CachedDashboard(key: "other-owner", data: original)
        container.mainContext.insert(unrelated)
        let failing = LocalRecordRepository(container: container) { _ in throw Injected.failed }
        do { try failing.write(["action": revised, "new-action": revised, "cursor": revised], removing: ["legacy"]); fatalError("Expected injected failure") }
        catch Injected.failed { }
        try check(records.read("action") == original)
        try check(records.read("new-action") == nil)
        try check(records.read("cursor") == original)
        try check(records.read("legacy") == Data([0,1,2]))
        precondition(container.mainContext.hasChanges, "Other owner must retain unsaved work")
        try check(records.read("other-owner") == nil, "Save must not commit another owner")
        try container.mainContext.save()
        try records.write(["unrelated-later-save": revised])
        let reopened = LocalRecordRepository(container: try open())
        try check(reopened.read("action") == original)
        try check(reopened.read("new-action") == nil, "Later saves cannot resurrect failed claims")
        try check(reopened.read("other-owner") == original)
        try records.write(["sources": revised, "cursor": revised], removing: ["unrelated-later-save"])
        try check(reopened.read("sources") == revised && reopened.read("cursor") == revised)
        try check(reopened.read("unrelated-later-save") == nil)
        do { let _: [String] = try records.decode("legacy")!; fatalError("Expected unreadable original") }
        catch is DecodingError { }
        try check(records.read("legacy") == Data([0,1,2]), "Decode must preserve unreadable original")
        // The expected bytes are compared under the write lease; a stale owner
        // cannot erase a later transaction, including an absent->present race.
        let captured=try records.read("action")
        try records.write(["action":revised],expected:["action":LocalRecordVersion(captured)])
        do { try reopened.write(["action":original,"must-not-save":original],expected:["action":LocalRecordVersion(captured)]);fatalError("Stale write accepted") }
        catch LocalRecordFailure.changed {}
        try check(records.read("action") == revised && records.read("must-not-save") == nil)
        try records.write(["claimed":original],expected:["claimed":.missing])
        do {try reopened.write(["claimed":revised],expected:["claimed":.missing]);fatalError("Duplicate claim accepted")}
        catch LocalRecordFailure.changed {}
        let lockURL=directory.appendingPathComponent("process.lock")
        var lease:LocalRecordFileLease?=try LocalRecordFileLease(url:lockURL)
        func probe()->Int32 {
            let child=Process();child.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);child.arguments=["--lease-probe",lockURL.path]
            do {try child.run();child.waitUntilExit();return child.terminationStatus} catch {fatalError("Probe failed")}
        }
        check(probe() == 23,"A second process cannot acquire the personal-store lease")
        withExtendedLifetime(lease) {};lease=nil
        check(probe() == 0,"Exit/release permits a subsequent owner without deleting the lock inode")
        struct Run:Codable {var location:Int;var length:Int}
        struct Formatting:Codable {var runs:[Run]}
        let opaqueRuns=Data(#"{"runs":[{"location":0,"length":5,"futureAnnotation":"left"},{"location":5,"length":5,"futureAnnotation":"right"}]}"#.utf8)
        let remaining=try LocalRecordCoding.preservingUnknown(Formatting(runs:[.init(location:5,length:5)]),original:opaqueRuns)
        let restoredRuns=(try JSONSerialization.jsonObject(with:remaining) as! [String:Any])["runs"] as! [[String:Any]]
        check(restoredRuns[0]["futureAnnotation"] as? String == "right","Removing an id-less row must not transfer another row's opaque metadata")
        do {_=try LocalRecordCoding.preservingUnknown(Formatting(runs:[.init(location:9,length:5)]),original:opaqueRuns);fatalError("Ambiguous opaque row edit accepted")}
        catch LocalRecordFailure.unsupportedFields {}
        struct Known:Codable {var known:Int}
        for number in ["1e127","1e-128","0.00000003","0.00000007","123456789012345678901234567890123456789"] {
            do {_=try LocalRecordCoding.preservingUnknown(Known(known:2),original:Data(("{\"known\":1,\"future\":"+number+"}").utf8));fatalError("Opaque numeric drift accepted")}
            catch LocalRecordFailure.unsupportedFields {}
        }
        _=try LocalRecordCoding.preservingUnknown(Known(known:2),original:Data(#"{"known":1,"future":1e3}"#.utf8))

        // Known typed Date/Double values may canonicalize their decimal spelling.
        // An ordinary edit must remain writable and retain exact typed values.
        let known=KnownNumericDocument(saved:Date(timeIntervalSinceReferenceDate:810000000.1234567),measurement:0.00000003,text:"Original")
        let knownBytes=try JSONEncoder().encode(known)
        try records.write(["known-numeric":knownBytes])
        var changedKnown=try JSONDecoder().decode(KnownNumericDocument.self,from:knownBytes)
        changedKnown.text="Edited"
        let changedKnownBytes=try LocalRecordCoding.preservingUnknown(changedKnown,original:knownBytes)
        try records.write(["known-numeric":changedKnownBytes],expected:["known-numeric":.bytes(knownBytes)])
        let readKnown=try reopened.decode("known-numeric",as:KnownNumericDocument.self)!
        check(readKnown.saved == known.saved && readKnown.measurement == known.measurement && readKnown.text == "Edited","Known numeric fields must not be rejected by opaque-field validation")

        for (index,token) in ["0.00000003","0.00000007","1e127","1e-128"].enumerated() {
            let original=Data(("{\"saved\":810000000.1234567,\"measurement\":0.00000003,\"text\":\"Original\",\"future\":{\"nested\":[true,null,{\"number\":"+token+"}]}}").utf8)
            let key="opaque-numeric-\(index)"
            try records.write([key:original])
            var updated=try JSONDecoder().decode(KnownNumericDocument.self,from:original);updated.text="Edited"
            do {
                let candidate=try LocalRecordCoding.preservingUnknown(updated,original:original)
                try records.write([key:candidate]);fatalError("Lossy opaque numeric field accepted")
            } catch LocalRecordFailure.unsupportedFields {}
            try check(records.read(key) == original,"Unsupported opaque numbers must retain exact original storage")
        }
        let exactOpaque=Data(#"{"saved":810000000.1234567,"measurement":0.00000003,"text":"Original","future\u004bey":{"decimal":0.12345678901234567890123456789012345678,"integer":12345678901234567890123456789012345678,"string":"quoted \" 0.00000003 \\ \u263a","bool":true,"nothing":null}}"#.utf8)
        var exactValue=try JSONDecoder().decode(KnownNumericDocument.self,from:exactOpaque);exactValue.text="Edited"
        let preservedExact=try LocalRecordCoding.preservingUnknown(exactValue,original:exactOpaque)
        let exactJSON=try JSONSerialization.jsonObject(with:preservedExact) as! [String:Any]
        let future=exactJSON["futureKey"] as! [String:Any]
        check((future["decimal"] as! NSNumber).stringValue == "0.12345678901234567890123456789012345678" && (future["integer"] as! NSNumber).stringValue == "12345678901234567890123456789012345678","Supported opaque decimals/integers must remain exact")
        check(future["string"] as? String == "quoted \" 0.00000003 \\ ☺" && future["nothing"] is NSNull,"Escaped keys/strings/null must not be mistaken for numeric tokens")

        // Syntax follows canonical UUID identity when rows move. Dropped rows
        // are explicit removals, not retained opaque dependencies.
        let droppedID=UUID(),retainedID=UUID()
        let oldRows=Data(("{\"rows\":[{\"id\":\""+droppedID.uuidString.lowercased()+"\",\"title\":\"Drop\",\"futureNumber\":0.00000003},{\"id\":\""+retainedID.uuidString.lowercased()+"\",\"title\":\"Keep\",\"futureNumber\":42}]}").utf8)
        var rows=try JSONDecoder().decode(OpaqueNumericRows.self,from:oldRows);rows.rows.removeFirst();rows.rows[0].title="Retained"
        let mergedRows=try JSONSerialization.jsonObject(with:LocalRecordCoding.preservingUnknown(rows,original:oldRows)) as! [String:Any]
        let row=(mergedRows["rows"] as! [[String:Any]])[0]
        check(row["futureNumber"] as? Int == 42 && row["title"] as? String == "Retained","Opaque syntax must follow retained UUID rows rather than old indices")
        let oldDictionary=Data(#"{"removed":{"known":1,"future":0.00000003},"retained":{"known":1,"future":42}}"#.utf8)
        let dictionary=try JSONSerialization.jsonObject(with:LocalRecordCoding.preservingUnknown(["retained":Known(known:2)],original:oldDictionary)) as! [String:[String:Any]]
        check(dictionary["removed"] == nil && dictionary["retained"]?["future"] as? Int == 42,"Dictionary removal must not validate or resurrect the removed opaque subtree")
        print("Local record checks passed: atomic persistence/CAS/leases, corrupt originals, typed high-precision Date/Double saves and exact opaque numeric/string/UUID/dictionary preservation.")
    }
}
