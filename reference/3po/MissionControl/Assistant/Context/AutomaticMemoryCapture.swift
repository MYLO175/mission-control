import Foundation

struct AutomaticMemoryCapture:Equatable {
    var records:[[String:String]]
    var dependencies:[MemoryDependency]
    var eligibleCount:Int
    var whatsappChats:Set<String> = []
    var pageContext:String = "{}"
    var contextPageDependencies:[String:String] = [:]
    var workspaceIDs:Set<UUID> = []
    /// Feature context excludes the ordinary-chat directory, whose labels are navigation metadata.
    static func pagePayload(_ text:String)->String {
        guard var object=(try? JSONSerialization.jsonObject(with:Data(text.utf8))) as? [String:Any] else {return "{}"}
        object.removeValue(forKey:"directory");object.removeValue(forKey:"directoryCount")
        return (try? JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])).map{String(decoding:$0,as:UTF8.self)} ?? "{}"
    }
    var context:String {
        var value:[String:Any]=["supportingRecords":records,"commitmentReports":CommitmentRules.context(records),"eligibleMemoryCount":eligibleCount,"selectedMemoryCount":records.count,"coverage":"Context pages and current working changes provide the readable context. Supporting records preserve original evidence, certainty and exact identities, and fill gaps while pages are being maintained. This is bounded permitted context, not a complete life history. Learning consent alone never enables another feature's source access."]
        if !contextPageDependencies.isEmpty,let pages=try? JSONSerialization.jsonObject(with:Data(pageContext.utf8)) {value["contextPages"]=pages}
        return (try? String(data:JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),encoding:.utf8)) ?? "{}"
    }
}
