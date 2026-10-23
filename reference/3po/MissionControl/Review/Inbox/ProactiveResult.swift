import Foundation
import CoreFoundation

/// A completed preparation result only. This tool never executes source or workspace actions.
enum ProactiveResultRules {
    static let toolName = "prepare_review"
    static let maximumArgumentBytes = 32_000
    static let instructions = "Return the finished comparison by calling pa.prepare_review exactly once. Do not answer in ordinary text or call any other tool. Return suggestions, projectTasks, handled, resolved and retirements arrays, using empty arrays when there is no supported result. Put local tasks inside existing projects in projectTasks; put Calendar and Apple Reminder proposals in suggestions. For a dated project milestone include its Calendar proposal and its local project task in their separate arrays. The combined suggestions/projectTasks limit is 24. This tool returns preparation data only: it does not create, change, complete, dismiss or send anything. Choose the suggestion schema for its action kind. Return null for each inapplicable field; each action variant constrains those fields to null. In suggestions, targetID belongs only to change/remove, connection only to projectTask/change/remove, scope only to remove, draft only to WhatsApp reply and projectID only to projectTask. Existing coverage belongs in handled or retirements, never a creation suggestion with targetID. New calendar/reminder suggestions do not require an existing native target. For a new Calendar creation, calendarID may select only an exact issued writable calendar from calendarPurposes when its supplied humanGuidance or complete individual human-written purpose unambiguously matches this action. Return null when applicable guidance is missing, partial, conflicting or ambiguous; local preparation then uses the ordinary native default. Never infer a purpose from a calendar title alone. Reminder suggestions and every other kind must use calendarID=null. Missing destination metadata is not a reason to omit a supported creation proposal. Only projectTask requires an exact existing projectID. A local task inside a human project must use kind projectTask and that projectID, never kind reminder; reminder is an Apple Reminder. For a supported project milestone return the Calendar proposal and the projectTask proposal separately. The handled and retirements sections each require their own issued targetID. Use null only for optional fields present in the selected schema. If there is no definite supported date, newDate, hasTime and endDate must all be null; never return an empty date string. Date-only values must use YYYY-MM-DD with hasTime=false. Timed values must use a full timestamp with seconds and an explicit UTC offset with hasTime=true. Start and end must use the same date mode. Project task due dates are date-only: preserve an exact source deadline time in the explanation/notes rather than encoding a timed local task. Preserve all exact evidence, action, date and ownership rules. Keep the entire result below 32000 UTF-8 bytes by using concise messages and evidence IDs instead of repeating Mail quotes. Return at most 24 suggestions, 12 handled and 12 resolved associations and 12 retirements; do not repeat proposals. Local validation remains authoritative. Review each source separately: dates and facts from one email cannot change an action in another. A booking confirmation is existing coverage, never cancellation. Preserve every distinct supported milestone before returning the result."

    static func tools(sourceAliases:Set<String>, evidenceAliases:Set<String>, nativeAliases:Set<String>, projectAliases:Set<String>, earlierAliases:Set<String>, confirmationAliases:Set<String>,retirementAliases:Set<String> = [],replacementAliases:Set<String>? = nil,changeSourceAliases:Set<String>? = nil,removalSourceAliases:Set<String>? = nil,writableNativeAliases:Set<String>? = nil,replacementAliasesBySource:[String:Set<String>]? = nil,removalUpgradeAliasesBySource:[String:Set<String>]? = nil,calendarIDs:Set<String> = []) -> [[String:Any]] {
        func text(_ limit:Int,nullable:Bool = false)->[String:Any] { ["type":nullable ? ["string","null"] : ["string"],"maxLength":limit] }
        func aliases(_ values:Set<String>,nullable:Bool = false)->[String:Any] {
            var choices:[Any]=values.sorted()
            if nullable { choices.append(NSNull()) }
            // Empty non-null alias sets cannot be selected; their containing array is bounded to zero.
            if choices.isEmpty { choices=[""] }
            return ["type":nullable ? ["string","null"] : ["string"],"enum":choices]
        }
        func object(_ fields:[String:[String:Any]])->[String:Any] {
            ["type":"object","properties":fields,"required":fields.keys.sorted(),"additionalProperties":false]
        }
        // Share issued alias sets through definitions: per-action variants must not
        // multiply the provider's total enum count or allow irrelevant mutation fields.
        var definitions:[String:[String:Any]]=[:]
        func reference(_ name:String,_ values:Set<String>,nullable:Bool = false)->[String:Any] {
            let existing=definitions.keys.sorted().first {definitions[$0]?["enum"] as? [String] == (values.isEmpty ? [""] : values.sorted())}
            let key=existing ?? (definitions[name] == nil ? name : name+"_"+String(definitions.count))
            if existing == nil {definitions[key]=aliases(values)}
            let ref:[String:Any]=["$ref":"#/$defs/"+key]
            return nullable ? ["anyOf":[ref,["type":"null"]]] : ref
        }
        func nativeReference(_ name:String,_ values:Set<String>)->[String:Any] {
            let groups=[Set(values.filter{$0.hasPrefix("event_")}),Set(values.filter{$0.hasPrefix("reminder_")}),Set(values.filter{$0.hasPrefix("completed_")}),Set(values.filter{!$0.hasPrefix("event_") && !$0.hasPrefix("reminder_") && !$0.hasPrefix("completed_")})]
            let rows=groups.enumerated().filter{!$0.element.isEmpty}.map{reference(name+String($0.offset),$0.element)}
            return rows.count == 1 ? rows[0] : rows.isEmpty ? reference(name,[]) : ["anyOf":rows]
        }
        let mail=Set(sourceAliases.filter{$0.hasPrefix("mail_")}),whatsapp=Set(sourceAliases.filter{$0.hasPrefix("wa_")})
        let primary=Set(evidenceAliases.filter{$0.hasSuffix(":primary")})
        let source=reference("source",sourceAliases),evidence=reference("evidence",evidenceAliases,nullable:true)
        let replacementIDs=replacementAliases ?? earlierAliases
        let replacement:[String:[String:Any]]=["replaces":["type":["array","null"],"maxItems":replacementIDs.isEmpty ? 0 : 3,"items":reference("replaceable",replacementIDs)],"replacementReason":replacementIDs.isEmpty ? ["type":"null"] : text(500,nullable:true)]
        func suggestion(_ kinds:[String],fields:[String:[String:Any]] = [:],replaces:Bool = false,allowedSources:Set<String>? = nil)->[String:Any] {
            let names=["mailID","kind","message","evidence","evidenceID","title","targetID","newDate","hasTime","connection","draft","replaces","replacementReason","scope","endDate","projectID","calendarID"]
            var common=Dictionary(uniqueKeysWithValues:names.map{($0,["type":"null"] as [String:Any])})
            common.merge(["kind":["type":"string","enum":kinds],"message":text(700,nullable:kinds == ["projectTask"] || kinds == ["remove"]),"title":text(300,nullable:true)]){_,new in new}
            common.merge(fields){_,new in new}
            if replaces {common.merge(replacement){_,new in new}}
            let mailSources=mail.intersection(allowedSources ?? sourceAliases),waSources=whatsapp.intersection(allowedSources ?? sourceAliases)
            var origins:[[String:Any]]=[]
            func sourceRows(_ values:Set<String>,mail:Bool) {
                func permitted(_ alias:String)->Set<String> {
                    guard replaces,let allowed=replacementAliasesBySource?[alias] else {return replacementIDs}
                    return allowed.union(kinds == ["remove"] ? removalUpgradeAliasesBySource?[alias] ?? [] : [])
                }
                let groups=Dictionary(grouping:values.sorted(),by:{permitted($0).sorted().joined(separator:"\n")})
                for key in groups.keys.sorted() {
                    let aliases=Set(groups[key]!),first=aliases.sorted()[0],allowed=permitted(first)
                    var row=common;row["mailID"]=reference("source_"+first,aliases)
                    if mail {row["evidence"]=["type":"null"];row["evidenceID"]=reference("evidence_"+first,Set(evidenceAliases.filter{reference in aliases.contains{reference.hasPrefix($0+":")}}))}
                    else {
                        let references=Set(evidenceAliases.filter{reference in aliases.contains{reference.hasPrefix($0+":action_")}})
                        if !references.isEmpty {row["evidenceID"]=reference("waEvidence_"+first,references);row["evidence"]=["type":"null"]}
                        else {row["evidenceID"]=["type":"null"];var quote=text(500);quote["minLength"]=8;row["evidence"]=quote}
                    }
                    if replaces,replacementAliasesBySource != nil {
                        row["replaces"]=["type":["array","null"],"maxItems":allowed.isEmpty ? 0 : 3,"items":reference("replacements_"+first,allowed)]
                        row["replacementReason"]=allowed.isEmpty ? ["type":"null"] : text(500,nullable:true)
                    }
                    origins.append(object(row))
                }
            }
            if kinds != ["reply"] {sourceRows(mailSources,mail:true)}
            sourceRows(waSources,mail:false)
            // With no sources, the containing array has maxItems=0 but still
            // requires a valid schema for items.
            if origins.isEmpty {common["mailID"]=source;common["evidence"]=["type":"null"];common["evidenceID"]=evidence;return object(common)}
            return origins.count == 1 ? origins[0] : ["anyOf":origins]
        }
        func date(_ timed:Bool,nullable:Bool = false)->[String:Any] {
            var value=text(40,nullable:nullable)
            value["pattern"]=timed ? #"^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d(Z|[+-]([01]\d|2[0-3]):[0-5]\d)$"# : #"^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$"#
            return value
        }
        let undated:[String:[String:Any]]=["newDate":["type":"null"],"hasTime":["type":"null"],"endDate":["type":"null"]]
        func dates(_ timed:Bool)->[String:[String:Any]] {["newDate":date(timed),"hasTime":["type":"boolean","enum":[timed]],"endDate":date(timed,nullable:true)]}
        let calendarChoice:[String:[String:Any]]=["calendarID":calendarIDs.isEmpty ? ["type":"null"] : reference("calendar",calendarIDs,nullable:true)]
        var variants=[suggestion(["calendar"],fields:undated.merging(calendarChoice){_,new in new},replaces:true),suggestion(["calendar"],fields:dates(false).merging(calendarChoice){_,new in new},replaces:true),suggestion(["calendar"],fields:dates(true).merging(calendarChoice){_,new in new},replaces:true),suggestion(["reminder"],fields:undated,replaces:true),suggestion(["reminder"],fields:dates(false),replaces:true),suggestion(["reminder"],fields:dates(true),replaces:true),suggestion(["update"],replaces:true),suggestion(["project"])]
        let project:[String:[String:Any]]=["projectID":reference("project",projectAliases),"connection":text(500),"title":text(160)]
        let projectTask:[String:Any]=["anyOf":[suggestion(["projectTask"],fields:undated.merging(project){_,new in new}),suggestion(["projectTask"],fields:dates(false).merging(project){_,new in new})]]
        let editable=Set((writableNativeAliases ?? nativeAliases).filter{$0.hasPrefix("event_") || $0.hasPrefix("reminder_")})
        if !editable.isEmpty && !(changeSourceAliases ?? sourceAliases).isEmpty {
            for timed in [false,true] {variants.append(suggestion(["change"],fields:["targetID":nativeReference("editable",editable),"newDate":date(timed),"hasTime":["type":"boolean","enum":[timed]],"connection":text(500)],replaces:true,allowedSources:changeSourceAliases))}
        }
        let removable=Set((writableNativeAliases ?? nativeAliases).filter{$0.hasPrefix("event_")})
        if !removable.isEmpty && !(removalSourceAliases ?? sourceAliases).isEmpty {variants.append(suggestion(["remove"],fields:["targetID":nativeReference("removable",removable),"scope":["type":"string","enum":["occurrence"]],"connection":text(500)],replaces:true,allowedSources:removalSourceAliases))}
        if !whatsapp.isEmpty {variants.append(suggestion(["reply"],fields:["mailID":reference("whatsapp",whatsapp),"evidenceID":["type":"null"],"draft":text(3000)]))}
        let handled=object(["mailID":reference("mail",mail),"targetID":nativeReference("handledNative",nativeAliases),"reason":text(500),"requestEvidenceID":reference("primary",primary),"allActionsAddressed":["type":"boolean","enum":[true]]])
        let resolved=object(["mailID":reference("mail",mail),"confirmationID":reference("confirmation",confirmationAliases),"requestEvidenceID":reference("primary",primary),"confirmationEvidenceID":reference("confirmationEvidence",Set(confirmationAliases.map{$0+":primary"})),"allActionsAddressed":["type":"boolean","enum":[true]],"reason":text(500)])
        let retirement=object(["reviewID":reference("earlier",earlierAliases),"targetID":nativeReference("retirement",retirementAliases),"reason":text(500)])
        var parameters=object([
            "suggestions":["type":"array","maxItems":sourceAliases.isEmpty ? 0 : 24,"items":["anyOf":variants]],
            "projectTasks":["type":"array","maxItems":sourceAliases.isEmpty || projectAliases.isEmpty ? 0 : 24,"items":projectTask],
            "handled":["type":"array","maxItems":mail.isEmpty || nativeAliases.isEmpty ? 0 : 12,"items":handled],
            "resolved":["type":"array","maxItems":mail.isEmpty || confirmationAliases.isEmpty ? 0 : 12,"items":resolved],
            "retirements":["type":"array","maxItems":earlierAliases.isEmpty || retirementAliases.isEmpty ? 0 : 12,"items":retirement]
        ])
        parameters["$defs"]=definitions
        return [["type":"namespace","name":"pa","description":"Return a source-grounded review preparation; no reads, saves or other actions.","tools":[["type":"function","name":toolName,"description":"Return separately reviewable suggestions and strictly supported existing-plan/completion associations.","strict":true,"parameters":parameters]]]]
    }

    /// Callers pass only the transport's completed calls, never partial argument deltas.
    static func completedJSON(_ calls:[(namespace:String?,name:String,arguments:String)]) throws -> String {
        guard !calls.isEmpty else {throw ReviewResultDiagnostic(section:.result,field:.tool,reason:.missingCompletedCall)}
        guard calls.count == 1 else {throw ReviewResultDiagnostic(section:.result,field:.tool,reason:.unexpectedCallCount)}
        let call=calls[0]
        guard (call.namespace == "pa" && call.name == toolName) || (call.namespace == nil && call.name == "pa."+toolName) else {throw ReviewResultDiagnostic(section:.result,field:.tool,reason:.unexpectedTool)}
        try validateEnvelope(call.arguments)
        guard var object=try JSONSerialization.jsonObject(with:Data(call.arguments.utf8)) as? [String:Any],let tasks=object.removeValue(forKey:"projectTasks") as? [[String:Any]] else {return call.arguments}
        let suggestions=(object["suggestions"] as? [[String:Any]] ?? [])+tasks
        guard suggestions.count <= 24 else {throw ReviewResultDiagnostic(section:.suggestions,field:.envelope,reason:.tooManyRows)}
        object["suggestions"]=suggestions
        return String(decoding:try JSONSerialization.data(withJSONObject:object,options:.sortedKeys),as:UTF8.self)
    }

    struct ValidatedRows<Value> {
        var values:[Value]=[]
        var issues:[String]=[]
        var entries:[ReviewRejectedEntry]=[]
        var acceptedRows:[Int]=[]
        var rejectedSources=Set<String>()
        var rejectedReviews=Set<String>()
    }
    /// Semantic failure is isolated to a row. Envelope/ownership validation happens
    /// first; a rejected row is never repaired into a native or project operation.
    static func validatedRows<Value>(_ response:String,section:ReviewResultDiagnostic.Section,sources:[String:(id:String,title:String)] = [:],decode:(String)throws->[Value])throws->ValidatedRows<Value> {
        guard let object=try JSONSerialization.jsonObject(with:Data(response.utf8)) as? [String:Any],let rows=object[section.rawValue] as? [[String:Any]] else {throw ReviewResultDiagnostic(section:section,field:.envelope,reason:.wrongType)}
        var result=ValidatedRows<Value>()
        for (index,row) in rows.enumerated() {
            var one:[String:Any]=["suggestions":[],"handled":[],"resolved":[],"retirements":[]];one[section.rawValue]=[row]
            do {
                let values=try decode(String(decoding:try JSONSerialization.data(withJSONObject:one),as:UTF8.self))
                result.values += values;result.acceptedRows += Array(repeating:index,count:values.count)
            }
            catch {
                var issue=(error as? ReviewResultDiagnostic) ?? .init(section:section,field:.envelope,reason:.invalidAssociation)
                issue.section=section;issue.row=index;result.issues.append(issue.localizedDescription)
                result.entries.append(rejectedEntry(row,diagnostic:issue,sources:sources))
                if let source=row["mailID"] as? String {result.rejectedSources.insert(source)}
                if let review=row["reviewID"] as? String {result.rejectedReviews.insert(review)}
                result.rejectedReviews.formUnion(row["replaces"] as? [String] ?? [])
            }
        }
        return result
    }

    static func rejectedEntry(_ row:[String:Any],diagnostic:ReviewResultDiagnostic,sources:[String:(id:String,title:String)])->ReviewRejectedEntry {
        func bounded(_ key:String,_ count:Int)->String? {(row[key] as? String).map{String($0.prefix(count))}}
        let source=(row["mailID"] as? String ?? row["reviewID"] as? String).flatMap{sources[$0]}
        return .init(diagnostic:diagnostic,suggestionTitle:bounded("title",300),kind:bounded("kind",40),sourceID:source?.id,sourceTitle:source.map{String($0.title.prefix(300))},evidenceID:bounded("evidenceID",80),proposedDate:bounded("newDate",80),proposedEndDate:bounded("endDate",80),hasTime:row["hasTime"] as? Bool,timeZoneID:TimeZone.current.identifier)
    }

    /// Structural checks diagnose association fields before their semantic validators run.
    /// Unknown keys and values never become diagnostic text or stored model fragments.
    static func validateEnvelope(_ text:String) throws {
        guard text.utf8.count <= maximumArgumentBytes else {throw ReviewResultDiagnostic(section:.result,field:.arguments,reason:.oversizedArguments)}
        let raw:Any
        do {raw=try JSONSerialization.jsonObject(with:Data(text.utf8))}
        catch {throw ReviewResultDiagnostic(section:.result,field:.envelope,reason:.malformedJSON)}
        guard let object=raw as? [String:Any] else {throw ReviewResultDiagnostic(section:.result,field:.envelope,reason:.wrongType)}
        guard Set(object.keys).isSubset(of:["suggestions","projectTasks","handled","resolved","retirements"]) else {throw ReviewResultDiagnostic(section:.result,field:.envelope,reason:.unsupportedField)}
        if let value=object["projectTasks"] {
            guard let tasks=value as? [[String:Any]],tasks.count <= 24 else {throw ReviewResultDiagnostic(section:.suggestions,field:.envelope,reason:.wrongType)}
            guard tasks.allSatisfy({$0["kind"] as? String == "projectTask"}) else {throw ReviewResultDiagnostic(section:.suggestions,field:.kind,reason:.unsupportedAction)}
            var canonical=object;canonical.removeValue(forKey:"projectTasks")
            canonical["suggestions"]=(object["suggestions"] as? [Any] ?? [])+tasks
            try validateEnvelope(String(decoding:try JSONSerialization.data(withJSONObject:canonical),as:UTF8.self))
        }
        for section in [ReviewResultDiagnostic.Section.suggestions,.handled,.resolved,.retirements] {
            if section == .retirements && object[section.rawValue] == nil {continue} // Legacy saved fictional responses remain readable.
            guard let value=object[section.rawValue] else {throw ReviewResultDiagnostic(section:section,field:.envelope,reason:.missingField)}
            guard let rows=value as? [Any] else {throw ReviewResultDiagnostic(section:section,field:.envelope,reason:.wrongType)}
            guard rows.count <= (section == .suggestions ? 24 : 12) else {throw ReviewResultDiagnostic(section:section,field:.envelope,reason:.tooManyRows)}
            let required:Set<String>,allowed:Set<String>
            switch section {
            case .suggestions:
                required=["mailID","kind"]
                allowed=["mailID","kind","message","evidence","evidenceID","title","targetID","newDate","hasTime","connection","draft","replaces","replacementReason","scope","endDate","projectID","calendarID"]
            case .handled:
                required=["mailID","targetID","reason","requestEvidenceID","allActionsAddressed"];allowed=required
            case .resolved:
                required=["mailID","confirmationID","requestEvidenceID","confirmationEvidenceID","allActionsAddressed","reason"];allowed=required
            case .retirements:
                required=["reviewID","targetID","reason"];allowed=required
            case .result:preconditionFailure("Result is not a row section")
            }
            for (index,value) in rows.enumerated() {
                func issue(_ field:ReviewResultDiagnostic.Field,_ reason:ReviewResultDiagnostic.Reason)->ReviewResultDiagnostic {.init(section:section,row:index,field:field,reason:reason)}
                guard let row=value as? [String:Any] else {throw issue(.envelope,.wrongType)}
                guard Set(row.keys).isSubset(of:allowed) else {throw issue(.envelope,.unsupportedField)}
                for key in required.sorted() where row[key] == nil || row[key] is NSNull {throw issue(ReviewResultDiagnostic.Field(rawValue:key) ?? .envelope,.missingField)}
                for key in row.keys.sorted() {
                    let field=ReviewResultDiagnostic.Field(rawValue:key) ?? .envelope
                    let value=row[key]!
                    if value is NSNull {continue}
                    if key == "hasTime" || key == "allActionsAddressed" {
                        guard let number=value as? NSNumber,CFGetTypeID(number) == CFBooleanGetTypeID() else {throw issue(field,.wrongType)}
                    } else if key == "replaces" {
                        guard let strings=value as? [String] else {throw issue(field,.wrongType)}
                        guard strings.count <= 3 else {throw issue(field,.tooManyRows)}
                    } else {
                        guard value is String else {throw issue(field,.wrongType)}
                    }
                }
            }
        }
    }
}
