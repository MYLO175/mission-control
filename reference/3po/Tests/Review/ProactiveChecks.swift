import Foundation
import CoreFoundation
@main struct ProactiveChecks {
    static func main() throws {
        try ReviewMailDedupChecks.run()
        try CrossSourceReviewChecks.run()
        precondition(ProactiveRules.nativeChangeCue("The Orion review is postponed.",removal:true))
        precondition(ProactiveRules.nativeChangeCue("The Orion report deadline is now 22 October.",removal:false))
        precondition(!ProactiveRules.nativeChangeCue("The Orion review is booked for 21 October.",removal:true))
        precondition(!ProactiveRules.nativeChangeCue("The Orion review is not cancelled.",removal:true))
        precondition(!ProactiveRules.whatsappReviewEnabled(manual:true,heartbeat:true,suggestions:false,heartbeatSource:false),"Manual heartbeat cannot expand brief-only WhatsApp access")
        precondition(ProactiveRules.whatsappReviewEnabled(manual:true,heartbeat:true,suggestions:true,heartbeatSource:false))
        precondition(ProactiveRules.whatsappReviewEnabled(manual:false,heartbeat:true,suggestions:false,heartbeatSource:true))
        let sourceText=String(repeating:"Fictional exact text. ",count:60)
        let exactQuotes=ProactiveRules.whatsappQuotes(sourceText)
        precondition(!exactQuotes.isEmpty && exactQuotes.allSatisfy{(8...500).contains($0.count) && sourceText.contains($0)})
        let sourceCandidate=DiscoveryCandidate(alias:"wa_0",mailID:"wa-source",evidence:"",followUpEvidence:"",actionEvidence:exactQuotes,sourceKind:"whatsapp",sourceText:sourceText)
        let quoteReference=#"{"suggestions":[{"mailID":"wa_0","kind":"update","message":"Fictional update","evidenceID":"wa_0:action_0","evidence":null}]}"#
        let boundQuote=try ProactiveRules.decode(quoteReference,candidates:[sourceCandidate],registration:"A",scope:"s",now:.now)
        precondition(boundQuote[0].evidence == exactQuotes[0],"The app attaches exact WhatsApp text; no model copying")
        do {_ = try ProactiveRules.decode(quoteReference.replacingOccurrences(of:"wa_0:action_0",with:"wa_1:action_0"),candidates:[sourceCandidate],registration:"A",scope:"s",now:.now);fatalError("Foreign quote accepted")} catch {}
        let candidates = [DiscoveryCandidate(alias:"mail_0",mailID:"real-A",evidence:"Please register by 10 October.",followUpEvidence:"10 October")]
        let good = #"{"suggestions":[{"mailID":"mail_0","kind":"reminder","message":"I could not spot a registration reminder. Shall I add one?","evidence":"Please register by 10 October."}]}"#
        let records = try ProactiveRules.decode(good,candidates:candidates,registration:"A",scope:"s",now:.now)
        precondition(records.count == 1 && records[0].mailID == "real-A" && records[0].deliveryID.hasPrefix("discovery:"))
        func rejected(_ text: String) { do { _ = try ProactiveRules.decode(text,candidates:candidates,registration:"A",scope:"s",now:.now); fatalError("Unexpected acceptance") } catch {} }
        rejected(good.replacingOccurrences(of:"mail_0",with:"invented"))
        rejected(good.replacingOccurrences(of:"Please register by 10 October.",with:"Invented deadline"))
        rejected(good.replacingOccurrences(of:"\"reminder\"",with:"\"send_email\""))
        rejected(#"{"suggestions":[{"mailID":"mail_0","kind":"calendar","message":"Hi","evidence":""}]}"#)
        let referenced = #"{"suggestions":[{"mailID":"mail_0","kind":"reminder","message":"Review registration","evidenceID":"mail_0:primary"}]}"#
        let referencedRecords=try ProactiveRules.decode(referenced,candidates:candidates,registration:"A",scope:"s",now:.now)
        precondition(referencedRecords.first?.evidence == candidates[0].evidence,"Issued evidence reference attaches the exact original quote")
        let followup=try ProactiveRules.decode(referenced.replacingOccurrences(of:"mail_0:primary",with:"mail_0:followup"),candidates:candidates,registration:"A",scope:"s",now:.now)
        precondition(followup.first?.evidence == candidates[0].followUpEvidence)
        rejected(referenced.replacingOccurrences(of:"mail_0:primary",with:"mail_1:primary"))
        rejected(referenced.replacingOccurrences(of:"mail_0:primary",with:"invented"))
        rejected(#"{"suggestions":[{"mailID":"mail_0","kind":"reminder","message":"Review registration","evidenceID":"mail_0:primary","evidence":"invented quote"}]}"#)
        precondition(ProactiveRules.unreported(records,prior:records,budget:3).isEmpty)
        let project=DiscoveryProjectTarget(id:UUID(),revision:UUID(),title:"Orion engineering project")
        let quotes=["Technical report submission: 4:00 pm, Thursday 21 January 2027.","Final report submission: 4:00 pm, Monday 31 May 2027.","Final presentation: Friday 4 June 2027 (Week 5)."]
        let compound=DiscoveryCandidate(alias:"mail_0",mailID:"compound",evidence:quotes[0],followUpEvidence:"",actionEvidence:quotes)
        let actions:[[String:Any]]=quotes.enumerated().flatMap { index,quote in
            ["calendar","projectTask"].map { kind in
                var row:[String:Any]=["mailID":"mail_0","kind":kind,"message":"Review this supported deadline.","evidenceID":"mail_0:action_"+String(index),"title":"Orion milestone "+String(index),"newDate":["2027-01-21T16:00:00Z","2027-05-31T16:00:00+01:00","2027-06-04"][index],"hasTime":index < 2]
                if kind == "projectTask" {row["projectID"]=project.id.uuidString;row["connection"]="Existing Orion project.";row["newDate"]=["2027-01-21","2027-05-31","2027-06-04"][index];row["hasTime"]=false}
                return row
            }
        }
        func actionDecode(_ rows:[[String:Any]]) throws -> [PADiscovery] {
            let json=String(decoding:try JSONSerialization.data(withJSONObject:["suggestions":rows]),as:UTF8.self)
            return try ProactiveRules.decode(json,candidates:[compound],registration:"A",scope:"s",now:.now,projects:[project.id.uuidString:project])
        }
        let separate=try actionDecode(actions)
        precondition(separate.count == 6 && Set(separate.map(\.id)).count == 6,"One email retains three dates and both destinations")
        precondition(separate[1].proposedProjectTask?.target == project && separate[1].proposedDate?.localDay == "2027-01-21")
        precondition(separate[4].proposedDate?.hasTime == false && !separate[4].needsDateClarification,"Explicit date with week annotation remains usable")
        precondition(ProactiveRules.unreported(separate,prior:separate).isEmpty,"Reruns do not duplicate compound actions")
        var oneDismissed=separate[0];oneDismissed.dismissed=true
        precondition(ProactiveRules.unreported(separate,prior:[oneDismissed]).count == 5,"Dismiss one destination preserves siblings")
        func rejectsActions(_ rows:[[String:Any]]) { do {_ = try actionDecode(rows);fatalError("Invalid action accepted")} catch {} }
        let repeatedCreation=try actionDecode([actions[0],actions[0]]);precondition(repeatedCreation.count == 1)
        var bad=actions[1];bad["projectID"]=UUID().uuidString;rejectsActions([bad])
        bad=actions[0];bad["evidenceID"]="mail_0:action_12";rejectsActions([bad])
        bad=actions[0];bad["newDate"]="2027-02-30";bad["hasTime"]=false;rejectsActions([bad])
        var dateOnlyTask=actions[1];dateOnlyTask["newDate"]="2027-01-21";dateOnlyTask["message"]=nil
        let localTask=try actionDecode([dateOnlyTask])[0]
        precondition(localTask.proposedDate?.hasTime == false && !localTask.message.isEmpty,"Project due date remains date-only and the app supplies an approval question")
        let restoredActions=try JSONDecoder().decode([PADiscovery].self,from:JSONEncoder().encode(separate))
        precondition(restoredActions == separate,"Exact dates and project revisions survive reopen")
        let capped=ProactiveRules.completing(.init(),versions:["compound":"v1"],context:"c",limited:true,reportedKeys:["compound"])
        precondition(capped.assessedSourceVersions?["compound"] == nil,"A full batch cannot claim all sibling actions assessed")
        // Completed typed transport is a preparation contract, never action execution.
        let envelope=String(decoding:try JSONSerialization.data(withJSONObject:["suggestions":actions,"handled":[],"resolved":[]]),as:UTF8.self)
        func completed(_ text:String,name:String = ProactiveResultRules.toolName,namespace:String? = "pa") throws -> String {
            try ProactiveResultRules.completedJSON([(namespace:namespace,name:name,arguments:text)])
        }
        let typed=try completed(envelope)
        let typedRecords=try ProactiveRules.decode(typed,candidates:[compound],registration:"A",scope:"s",now:.now,projects:[project.id.uuidString:project])
        precondition(typedRecords.count == 6 && Set(typedRecords.map(\.kind)) == ["calendar","projectTask"])
        let separated=String(decoding:try JSONSerialization.data(withJSONObject:["suggestions":[actions[0]],"projectTasks":[actions[1]],"handled":[],"resolved":[],"retirements":[]]),as:UTF8.self)
        let separatedJSON=try completed(separated)
        let separateDestinations=try ProactiveRules.decode(separatedJSON,candidates:[compound],registration:"A",scope:"s",now:.now,projects:[project.id.uuidString:project])
        precondition(separateDestinations.count == 2 && Set(separateDestinations.map(\.kind)) == ["calendar","projectTask"],"Typed project task array retains both independent destinations")
        var unsupportedSibling=actions[1];unsupportedSibling["projectID"]="unissued"
        let partlyValid=String(decoding:try JSONSerialization.data(withJSONObject:["suggestions":[actions[0],unsupportedSibling],"handled":[],"resolved":[],"retirements":[]]),as:UTF8.self)
        let kept=try ProactiveResultRules.validatedRows(partlyValid,section:.suggestions) {try ProactiveRules.decode($0,candidates:[compound],registration:"A",scope:"s",now:.now,projects:[project.id.uuidString:project])}
        precondition(kept.values.count == 1 && kept.issues.count == 1 && kept.rejectedSources == ["mail_0"],"Unsupported sibling is withheld without discarding a separately validated action")
        let qualified=try completed(envelope,name:"pa.prepare_review",namespace:nil);precondition(qualified == envelope)
        func diagnostic(_ section:ReviewResultDiagnostic.Section = .suggestions,_ row:Int? = 0,_ field:ReviewResultDiagnostic.Field,_ reason:ReviewResultDiagnostic.Reason,_ run:()throws->Void) {
            do {try run();fatalError("Invalid typed result accepted")}
            catch let error as ReviewResultDiagnostic {
                precondition(error == .init(section:section,row:row,field:field,reason:reason),"Unexpected safe diagnostic: \(error)")
                precondition(!error.localizedDescription.contains("private-SECRET"),"Diagnostic leaked model/source data")
            } catch {fatalError("Unexpected error class: \(type(of:error))")}
        }
        diagnostic(.result,nil,.tool,.missingCompletedCall) {_ = try ProactiveResultRules.completedJSON([])}
        diagnostic(.result,nil,.tool,.unexpectedCallCount) {_ = try ProactiveResultRules.completedJSON([(namespace:"pa",name:"prepare_review",arguments:envelope),(namespace:"pa",name:"prepare_review",arguments:envelope)])}
        diagnostic(.result,nil,.tool,.unexpectedTool) {_ = try completed(envelope,name:"private-SECRET")}
        diagnostic(.result,nil,.tool,.unexpectedTool) {_ = try completed(envelope,namespace:"private-SECRET")}
        diagnostic(.result,nil,.envelope,.malformedJSON) {_ = try completed("private-SECRET")}
        diagnostic(.result,nil,.envelope,.malformedJSON) {_ = try completed("{\"suggestions\":[")}
        diagnostic(.result,nil,.envelope,.wrongType) {_ = try completed("[]")}
        diagnostic(.handled,nil,.envelope,.missingField) {_ = try completed("{\"suggestions\":[],\"resolved\":[]}")}
        diagnostic(.result,nil,.envelope,.unsupportedField) {_ = try completed("{\"suggestions\":[],\"handled\":[],\"resolved\":[],\"private-SECRET\":true}")}
        diagnostic(.result,nil,.arguments,.oversizedArguments) {_ = try completed(String(repeating:"é",count:16001))}
        let blank="{\"suggestions\":[],\"handled\":[],\"resolved\":[]}"
        let boundary=blank+String(repeating:" ",count:32000-blank.utf8.count)
        let atBoundary=try completed(boundary);precondition(atBoundary == boundary)
        diagnostic(.result,nil,.arguments,.oversizedArguments) {_ = try completed(boundary+" ")}
        diagnostic(.suggestions,0,.envelope,.unsupportedField) {_ = try completed("{\"suggestions\":[{\"mailID\":\"mail_0\",\"kind\":\"update\",\"private-SECRET\":true}],\"handled\":[],\"resolved\":[]}")}
        diagnostic(.suggestions,0,.hasTime,.wrongType) {_ = try completed("{\"suggestions\":[{\"mailID\":\"mail_0\",\"kind\":\"calendar\",\"hasTime\":1}],\"handled\":[],\"resolved\":[]}")}
        diagnostic(.handled,0,.reason,.missingField) {_ = try completed("{\"suggestions\":[],\"handled\":[{\"mailID\":\"mail_0\",\"targetID\":\"event_0\",\"requestEvidenceID\":\"mail_0:primary\",\"allActionsAddressed\":true}],\"resolved\":[]}")}
        diagnostic(.resolved,0,.confirmationID,.wrongType) {_ = try completed("{\"suggestions\":[],\"handled\":[],\"resolved\":[{\"mailID\":\"mail_0\",\"confirmationID\":3,\"requestEvidenceID\":\"mail_0:primary\",\"confirmationEvidenceID\":\"completion_0:primary\",\"allActionsAddressed\":true,\"reason\":\"private-SECRET\"}]}")}
        var invalidAction=actions[0];invalidAction["kind"]="private-SECRET"
        diagnostic(.suggestions,0,.kind,.unsupportedAction) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["mailID"]="private-SECRET"
        diagnostic(.suggestions,0,.mailID,.unissuedSource) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["evidenceID"]="private-SECRET"
        diagnostic(.suggestions,0,.evidenceID,.unissuedEvidence) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["connection"]="private-SECRET"
        diagnostic(.suggestions,0,.connection,.incompatibleFields) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["newDate"]="2027-02-30";invalidAction["hasTime"]=false
        diagnostic(.suggestions,0,.newDate,.impossibleDate) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction.removeValue(forKey:"hasTime")
        diagnostic(.suggestions,0,.hasTime,.missingField) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["message"]=String(repeating:"a",count:701)
        diagnostic(.suggestions,0,.message,.tooLong) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["message"]=""
        diagnostic(.suggestions,0,.message,.emptyValue) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["endDate"]="2026-01-01"
        diagnostic(.suggestions,0,.endDate,.timeFlagMismatch) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["newDate"]="2027-01-21";invalidAction["hasTime"]=true
        diagnostic(.suggestions,0,.newDate,.timeFlagMismatch) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["hasTime"]=false
        diagnostic(.suggestions,0,.newDate,.timeFlagMismatch) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["newDate"]="2027-01-21T16:00:00+99:00"
        diagnostic(.suggestions,0,.newDate,.impossibleDate) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["newDate"]="2027-02-30T16:00:00Z"
        diagnostic(.suggestions,0,.newDate,.impossibleDate) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["newDate"]="21 January 2027"
        diagnostic(.suggestions,0,.newDate,.dateFormat) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[1];invalidAction["newDate"]="2027-01-21T16:00:00Z";invalidAction["hasTime"]=true
        diagnostic(.suggestions,0,.hasTime,.projectTimeUnsupported) {_ = try actionDecode([invalidAction])}
        invalidAction=actions[0];invalidAction["endDate"]="2027-01-20T16:00:00Z"
        diagnostic(.suggestions,0,.endDate,.endBeforeStart) {_ = try actionDecode([invalidAction])}
        var unresolved=compound;unresolved.actionEvidence=["Final presentation in week five."]
        var unresolvedRow=actions[0];unresolvedRow["evidenceID"]="mail_0:action_0"
        diagnostic(.suggestions,0,.newDate,.unanchoredWeek) {_ = try ProactiveRules.decode(String(decoding:JSONSerialization.data(withJSONObject:["suggestions":[unresolvedRow]]),as:UTF8.self),candidates:[unresolved],registration:"A",scope:"s",now:.now)}
        invalidAction=actions[0];invalidAction["newDate"]="2027-02-30";invalidAction["hasTime"]=false
        let diagnosticResponse=String(decoding:try JSONSerialization.data(withJSONObject:["suggestions":[actions[0],invalidAction],"handled":[],"resolved":[],"retirements":[]]),as:UTF8.self)
        let detailed=try ProactiveResultRules.validatedRows(diagnosticResponse,section:.suggestions,sources:["mail_0":("exact-source","Orion project schedule")]) {try ProactiveRules.decode($0,candidates:[compound],registration:"A",scope:"s",now:.now)}
        let entry=try JSONDecoder().decode(ReviewRejectedEntry.self,from:JSONEncoder().encode(detailed.entries[0]))
        precondition(detailed.values.count == 1 && entry.diagnostic.row == 1 && entry.diagnostic.reason == .impossibleDate && entry.proposedDate == "2027-02-30" && entry.hasTime == false && entry.sourceTitle == "Orion project schedule" && entry.sourceID == "exact-source" && entry.suggestionTitle == invalidAction["title"] as? String)
        precondition(entry.display.contains("2027-02-30") && entry.display.contains("Orion project schedule") && entry.display.contains("valid calendar date"))
        let metadata=String(decoding:try JSONEncoder().encode(entry),as:UTF8.self)
        precondition(!metadata.contains(compound.actionEvidence[0]),"Rejected-entry diagnostics do not duplicate source bodies/quotes")
        let legacy=try JSONDecoder().decode(ProactiveProgress.self,from:Data(#"{"day":"","attempts":0,"delivered":0,"paused":false}"#.utf8))
        precondition(legacy.validationEntries == nil,"Legacy progress survives the additive diagnostic field")
        invalidAction=actions[1];invalidAction["projectID"]="private-SECRET"
        diagnostic(.suggestions,0,.projectID,.invalidTarget) {_ = try actionDecode([invalidAction])}
        let repeatedAction=try actionDecode([actions[0],actions[0]])
        precondition(repeatedAction.count == 1,"Identical rows produce one saved action")
        // Invalid sibling rejects the entire batch, so no partial project/calendar approval exists.
        diagnostic(.suggestions,1,.projectID,.invalidTarget) {_ = try actionDecode([actions[0],invalidAction])}
        diagnostic(.suggestions,0,.kind,.missingField) {_ = try ProactiveRules.decode("{\"suggestions\":[{\"mailID\":\"private-SECRET\"}]}",candidates:[],registration:"A",scope:"s",now:.now)}
        diagnostic(.suggestions,0,.message,.wrongType) {_ = try ProactiveRules.decode("{\"suggestions\":[{\"mailID\":\"mail_0\",\"kind\":\"update\",\"message\":3}]}",candidates:[],registration:"A",scope:"s",now:.now)}
        // The real transport never exposes unfinished review calls, even after item.done.
        let item:[String:Any]=["type":"function_call","status":"completed","call_id":"review-fixture","name":"prepare_review","namespace":"pa","arguments":envelope]
        let doneEvent="data: "+String(decoding:try JSONSerialization.data(withJSONObject:["type":"response.output_item.done","output_index":0,"item":item]),as:UTF8.self)
        var pendingReview=ChatGPTStream(allowsTools:true)
        _ = try pendingReview.line(doneEvent)
        precondition(pendingReview.calls.isEmpty)
        do {_ = try pendingReview.finish();fatalError("Unfinished review accepted")} catch ChatGPTStream.Failure.interrupted {}
        var finishedReview=ChatGPTStream(allowsTools:true)
        _ = try finishedReview.line(doneEvent)
        _ = try finishedReview.line("data: {\"type\":\"response.completed\"}")
        _ = try finishedReview.finish()
        let streamedJSON=try ProactiveResultRules.completedJSON(finishedReview.calls.map{($0.namespace,$0.name,$0.arguments)})
        precondition(streamedJSON == envelope,"Completed output_item.done fallback retains review preparation")
        var invalidStatus=item;invalidStatus["status"]="in_progress"
        var incompleteReview=ChatGPTStream(allowsTools:true)
        do {
            _ = try incompleteReview.line("data: "+String(decoding:try JSONSerialization.data(withJSONObject:["type":"response.completed","response":["output":[invalidStatus]]]),as:UTF8.self))
            fatalError("Incomplete review call accepted")
        } catch ChatGPTStream.Failure.invalid {}
        let declarations=ProactiveResultRules.tools(sourceAliases:["mail_0","wa_0"],evidenceAliases:["mail_0:primary","mail_0:action_0"],nativeAliases:["event_0"],projectAliases:[project.id.uuidString],earlierAliases:["review_0"],confirmationAliases:["completion_0"],calendarIDs:["calendar_studies"])
        let namespace=declarations[0],functions=namespace["tools"] as! [[String:Any]],parameters=functions[0]["parameters"] as! [String:Any]
        precondition(namespace["name"] as? String == "pa" && functions[0]["strict"] as? Bool == true)
        precondition(Set(parameters["required"] as! [String]) == ["suggestions","projectTasks","handled","resolved","retirements"])
        // Validate representative payloads against the issued schema itself. This
        // regression catches cross-kind combinations before they reach the provider.
        func matches(_ value:Any,_ schema:[String:Any],root:[String:Any])->Bool {
            if let ref=schema["$ref"] as? String {
                let name=String(ref.split(separator:"/").last!)
                guard let definition=(root["$defs"] as? [String:[String:Any]])?[name] else {return false}
                return matches(value,definition,root:root)
            }
            if let options=schema["anyOf"] as? [[String:Any]] {return options.contains{matches(value,$0,root:root)}}
            let types=(schema["type"] as? [String]) ?? (schema["type"] as? String).map{[$0]} ?? []
            let null=value is NSNull
            let boolean=(value as? NSNumber).map{CFGetTypeID($0) == CFBooleanGetTypeID()} ?? false
            let validType=types.contains {type in
                switch type {case "null":return null;case "string":return value is String;case "boolean":return boolean;case "object":return value is [String:Any];case "array":return value is [Any];default:return false}
            }
            guard validType else {return false}
            if let choices=schema["enum"] as? [Any],!choices.contains(where:{($0 as? NSObject)?.isEqual(value) == true}) {return false}
            if let text=value as? String,let maximum=schema["maxLength"] as? Int,text.count > maximum {return false}
            if let text=value as? String,let pattern=schema["pattern"] as? String,text.range(of:pattern,options:.regularExpression) == nil {return false}
            if let array=value as? [Any] {
                if let maximum=schema["maxItems"] as? Int,array.count > maximum {return false}
                if let items=schema["items"] as? [String:Any],!array.allSatisfy({matches($0,items,root:root)}) {return false}
            }
            if let object=value as? [String:Any] {
                let fields=schema["properties"] as? [String:[String:Any]] ?? [:]
                if let required=schema["required"] as? [String],!required.allSatisfy({object[$0] != nil}) {return false}
                if schema["additionalProperties"] as? Bool == false,!Set(object.keys).isSubset(of:Set(fields.keys)) {return false}
                return object.allSatisfy{key,value in fields[key].map{matches(value,$0,root:root)} ?? true}
            }
            return true
        }
        func schemaAccepts(_ rows:[[String:Any]],projectRows:[[String:Any]] = [])->Bool {
            let fields=["mailID","kind","message","evidence","evidenceID","title","targetID","newDate","hasTime","connection","draft","replaces","replacementReason","scope","endDate","projectID","calendarID"]
            let padded=rows.map{row in var full=Dictionary(uniqueKeysWithValues:fields.map{($0,NSNull() as Any)});full.merge(row){_,new in new};return full}
            let paddedProjects=projectRows.map{row in var full=Dictionary(uniqueKeysWithValues:fields.map{($0,NSNull() as Any)});full.merge(row){_,new in new};return full}
            return matches(["suggestions":padded,"projectTasks":paddedProjects,"handled":[],"resolved":[],"retirements":[]],parameters,root:parameters)
        }
        var creation:[String:Any]=["mailID":"mail_0","kind":"reminder","message":"Register","evidence":NSNull(),"evidenceID":"mail_0:primary","title":"Register","newDate":NSNull(),"hasTime":NSNull(),"endDate":NSNull(),"replaces":NSNull(),"replacementReason":NSNull()]
        precondition(schemaAccepts([creation]))
        var calendarCreation=creation;calendarCreation["kind"]="calendar";calendarCreation["calendarID"]="calendar_studies"
        precondition(schemaAccepts([calendarCreation]),"Calendar destination is limited to an exact issued writable choice")
        calendarCreation["calendarID"]="calendar_unissued";precondition(!schemaAccepts([calendarCreation]))
        calendarCreation["calendarID"]=NSNull();precondition(schemaAccepts([calendarCreation]),"An ambiguous or missing purpose retains the local native default")
        var reminderDestination=creation;reminderDestination["calendarID"]="calendar_studies"
        precondition(!schemaAccepts([reminderDestination]),"Calendar choices cannot leak into Reminder or other action kinds")
        let calendarSource=SourceOption(id:"calendar_studies",title:"Studies",account:"Fictional University",writable:true,providerID:"provider-a")
        let issuedCalendar=DiscoveryCalendarDestination(calendarSource,contextPageDependencies:["calendar-guide:calendar_studies":"guide-v1"])
        let calendarOutput=#"{"suggestions":[{"mailID":"mail_0","kind":"calendar","message":"Add the registration date","evidenceID":"mail_0:primary","calendarID":"calendar_studies"}]}"#
        let selectedCalendar=try ProactiveRules.decode(calendarOutput,candidates:candidates,registration:"A",scope:"s",now:.now,calendars:[calendarSource.id:issuedCalendar])[0]
        precondition(selectedCalendar.proposedCalendarDestination == issuedCalendar && issuedCalendar.matches(calendarSource))
        let reopenedCalendar=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(selectedCalendar))
        precondition(reopenedCalendar.proposedCalendarDestination == issuedCalendar && records[0].proposedCalendarDestination == nil,"New destination receipts are additive and persist exactly")
        var legacyCalendarObject=try JSONSerialization.jsonObject(with:JSONEncoder().encode(selectedCalendar)) as! [String:Any]
        legacyCalendarObject.removeValue(forKey:"proposedCalendarDestination")
        let legacyCalendar=try JSONDecoder().decode(PADiscovery.self,from:JSONSerialization.data(withJSONObject:legacyCalendarObject))
        precondition(legacyCalendar.proposedCalendarDestination == nil,"Previously saved proposals retain native-default preparation")
        do {_ = try ProactiveRules.decode(calendarOutput,candidates:candidates,registration:"A",scope:"s",now:.now);fatalError("Unissued Calendar destination accepted")} catch {}
        do {_ = try ProactiveRules.decode(calendarOutput.replacingOccurrences(of:"\"calendar\"",with:"\"reminder\""),candidates:candidates,registration:"A",scope:"s",now:.now,calendars:[calendarSource.id:issuedCalendar]);fatalError("Calendar destination accepted for a Reminder")} catch {}
        var changedAccount=calendarSource;changedAccount.account="Other account";precondition(!issuedCalendar.matches(changedAccount))
        changedAccount=calendarSource;changedAccount.providerID="provider-b";precondition(!issuedCalendar.matches(changedAccount))
        changedAccount=calendarSource;changedAccount.writable=false;precondition(!issuedCalendar.matches(changedAccount))
        changedAccount=calendarSource;changedAccount.title="Renamed studies";precondition(issuedCalendar.matches(changedAccount),"Cosmetic labels do not retarget an approved destination")
        var reworded=selectedCalendar;reworded.proposedCalendarDestination?.contextPageDependencies=["calendar-guide:calendar_studies":"guide-v2"]
        precondition(ProactiveRules.sameProposal(selectedCalendar,reworded),"Guide edits alone do not duplicate an unchanged exact destination")
        reworded.proposedCalendarDestination?.sourceID="calendar_personal"
        precondition(!ProactiveRules.sameProposal(selectedCalendar,reworded),"Distinct concrete destinations remain independent choices")
        creation["targetID"]="event_0";precondition(!schemaAccepts([creation]),"Creation with targetID must be impossible under the strict schema")
        creation.removeValue(forKey:"targetID");creation["connection"]="Already covered";precondition(!schemaAccepts([creation]))
        creation.removeValue(forKey:"connection");creation["newDate"]="2027-01-21";creation["hasTime"]=false;precondition(schemaAccepts([creation]))
        creation["hasTime"]=false;precondition(schemaAccepts([creation]))
        creation["hasTime"]=true;precondition(!schemaAccepts([creation]),"A date-only value cannot be marked timed in the strict schema")
        creation["newDate"]="2027-01-21T16:00:00Z";precondition(schemaAccepts([creation]))
        creation["hasTime"]=false;precondition(!schemaAccepts([creation]),"A timestamp cannot be marked date-only in the strict schema")
        creation["hasTime"]=true;creation["endDate"]="2027-01-22";precondition(!schemaAccepts([creation]),"Start and end date modes cannot differ")
        creation["endDate"]=NSNull();creation["newDate"]="2027-01-21T25:00:00Z";precondition(!schemaAccepts([creation]))
        creation["newDate"]="";precondition(!schemaAccepts([creation]),"An empty string cannot encode an undated task")
        precondition(schemaAccepts([],projectRows:[actions[1]]))
        var timedTask=actions[1];timedTask["newDate"]="2027-01-21T16:00:00Z";timedTask["hasTime"]=true
        precondition(!schemaAccepts([],projectRows:[timedTask]),"The strict project-task schema accepts only date-only due values")
        var revisedAssessment=separate[0];revisedAssessment.sourceAssessmentRevision="new-assessment"
        precondition(ProactiveRules.unreported([revisedAssessment],prior:[separate[0]]).isEmpty,"Reassessment cannot duplicate a pending concrete action")

        var change:[String:Any]=["mailID":"mail_0","kind":"change","message":"Moved","evidence":NSNull(),"evidenceID":"mail_0:primary","title":NSNull(),"targetID":"event_0","newDate":"2027-01-21","hasTime":false,"connection":"Same plan","replaces":NSNull(),"replacementReason":NSNull()]
        precondition(schemaAccepts([change]));change["targetID"]="completed_0";precondition(!schemaAccepts([change]))
        var schemaReply:[String:Any]=["mailID":"wa_0","kind":"reply","message":"Reply","evidence":"Please schemaReply to this fictional message.","evidenceID":NSNull(),"title":NSNull(),"draft":"Thanks."]
        precondition(schemaAccepts([schemaReply]));schemaReply["mailID"]="mail_0";precondition(!schemaAccepts([schemaReply]))
        // Mixed retirement and creation remains one valid preparation; irrelevant
        // fields still fail local semantic validation rather than being discarded.
        var invalidCreation=actions[0];invalidCreation["targetID"]="event_0"
        diagnostic(.suggestions,0,.targetID,.incompatibleFields) {_ = try actionDecode([invalidCreation])}
        let largeEvents=Set((0..<200).map{"event_\($0)"}),largeReminders=Set((0..<120).map{"reminder_\($0)"}),largeCompleted=Set((0..<80).map{"completed_\($0)"})
        let large=ProactiveResultRules.tools(sourceAliases:["mail_0"],evidenceAliases:["mail_0:primary"],nativeAliases:largeEvents.union(largeReminders).union(largeCompleted),projectAliases:[],earlierAliases:["review_0"],confirmationAliases:["mail_0"],retirementAliases:largeEvents.union(largeReminders).union((0..<60).map{"task_\($0)"}),calendarIDs:Set((0..<60).map{"calendar_\($0)"}))
        func enumCount(_ value:Any)->Int {
            if let object=value as? [String:Any] {return (object["enum"] as? [Any])?.count ?? object.values.reduce(0){$0+enumCount($1)}}
            if let array=value as? [Any] {return array.reduce(0){$0+enumCount($1)}}
            return 0
        }
        precondition(enumCount(large) <= 1000,"Maximum native coverage remains inside the strict schema's enum limit")
        precondition(JSONSerialization.isValidJSONObject(declarations))
        var dismissed = records[0]; dismissed.dismissed = true
        precondition(ProactiveRules.unreported(records,prior:[dismissed],budget:3).isEmpty)
        var anotherAccount = dismissed; anotherAccount.registration = "B"
        precondition(ProactiveRules.unreported(records,prior:[anotherAccount],budget:1).count == 1)
        precondition(ProactiveRules.unreported(records,prior:[],budget:0).isEmpty)
        var progress = ProactiveProgress(); precondition(ProactiveRules.allowed(progress,now:.now))
        progress.paused = true; precondition(!ProactiveRules.allowed(progress,now:.now)); precondition(ProactiveRules.allowed(progress,now:.now,manual:true))
        progress.delivered = 300; precondition(ProactiveRules.allowed(progress,now:.now,manual:true))
        progress.delivered = 0; progress.paused = false; progress.attempts = 4; precondition(!ProactiveRules.allowed(progress,now:.now))
        progress.attempts = 0; progress.lastAttempt = .now; precondition(!ProactiveRules.allowed(progress,now:.now))
        var heartbeat=ProactiveProgress();heartbeat.attempts=4
        precondition(ProactiveRules.allowed(heartbeat,now:.now,heartbeat:true))
        heartbeat.attempts=8;precondition(!ProactiveRules.allowed(heartbeat,now:.now,heartbeat:true))
        let update=try ProactiveRules.decode(good.replacingOccurrences(of:"\"reminder\"",with:"\"update\""),candidates:candidates,registration:"A",scope:"s",now:.now)[0]
        let updateTurn=AssistantTurn(role:"assistant",content:update.message,completed:true,deliveryID:update.deliveryID)
        precondition(ProactiveReviewRules.reference("yes",turns:[updateTurn],records:[update]) == nil, "Informational updates do not offer or implicitly create native items")
        var claimed=update;claimed.notificationClaimed=true
        let restoredClaim=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(claimed))
        precondition(restoredClaim.notificationClaimed == true)
        let state = ProactiveState(accounts:["A":progress],records:[dismissed])
        let restored = try JSONDecoder().decode(ProactiveState.self,from:JSONEncoder().encode(state))
        precondition(restored.records == [dismissed] && restored.accounts["A"]?.lastAttempt != nil)
        let suggestion = AssistantTurn(role:"assistant",content:records[0].message,completed:true,deliveryID:records[0].deliveryID)
        for request in ["yes","Yes, please!","add that","put it in my reminders","Please add a reminder for that","add that pls"] {
            precondition(ProactiveReviewRules.reference(request,turns:[suggestion],records:records)?.id == records[0].id)
        }
        for request in ["don't add that","An email says: yes please", "add that and delete the original", "add that to my calendar", "yes, but only if I accept", "what about that?", ""] {
            precondition(ProactiveReviewRules.reference(request,turns:[suggestion],records:records) == nil)
        }
        precondition(ProactiveReviewRules.reference("yes",turns:[suggestion],records:[]) == nil)
        precondition(ProactiveReviewRules.reference("yes",turns:[suggestion],records:[dismissed]) == nil)
        let unrelated = AssistantTurn(role:"assistant",content:"Your unrelated question is answered.",completed:true)
        precondition(ProactiveReviewRules.reference("yes",turns:[suggestion,unrelated],records:records) == nil)
        let interrupted = AssistantTurn(role:"assistant",content:"Partial answer",completed:false)
        precondition(ProactiveReviewRules.reference("yes",turns:[suggestion,interrupted],records:records) == nil)
        var pa = AssistantConversation(accountID:"A",title:"Your PA",turns:[suggestion]); pa.isPrimary = true
        let study = AssistantConversation(accountID:"A",title:"Study",isTopic:true)
        precondition(ProactiveReviewRules.reference("yes",turns:ConversationRules.thread(feed:pa,topic:study),records:records) == nil)
        precondition(ProactiveReviewRules.reference("yes",turns:ConversationRules.thread(feed:pa,topic:nil),records:records) != nil)
        let message=WhatsAppReadMessage(id:"same-id",chat:"family",sender:"person",text:"Alex, please book the train for Friday.",sentByMe:false,time:Date.now.timeIntervalSince1970*1000)
        let candidate=DiscoveryCandidate(alias:"wa_0",mailID:"issued-wa",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceChatID:message.chat,sourceMessageID:message.id,sourceIdentity:"linked",sourceRevision:SourceContextRules.revision(message),sourceLabel:"Family",sourceText:message.text)
        let response=#"{"suggestions":[{"mailID":"wa_0","kind":"reminder","title":"Book the train","message":"Your family asked you to book the train. Shall I add a reminder?","evidence":"please book the train for Friday."}]}"#
        let wa=try ProactiveRules.decode(response,candidates:[candidate],registration:"A",scope:"s",now:.now)[0]
        var access=WhatsAppAccess(enabled:true,chats:["family"])
        precondition(ProactiveRules.permittedWhatsApp(wa,access:access,identity:"linked",messages:[message]))
        precondition(!ProactiveRules.permittedWhatsApp(wa,access:access,identity:"other",messages:[message]))
        precondition(!ProactiveRules.permittedWhatsApp(wa,access:access,identity:"linked",messages:[]))
        let edited=WhatsAppReadMessage(id:message.id,chat:message.chat,sender:message.sender,text:"Already booked, thanks",sentByMe:false,time:message.time)
        precondition(!ProactiveRules.permittedWhatsApp(wa,access:access,identity:"linked",messages:[edited]))
        access.chats=[];precondition(!ProactiveRules.permittedWhatsApp(wa,access:access,identity:"linked",messages:[message]))
        var changed=wa;changed.sourceRevision="changed"
        precondition(ProactiveRules.unreported([changed],prior:[wa],budget:1).count == 1)
        do { _=try ProactiveRules.decode(response.replacingOccurrences(of:"please book the train for Friday.",with:"invented evidence"),candidates:[candidate],registration:"A",scope:"s",now:.now);fatalError("Invented WhatsApp evidence accepted") } catch {}
        let waReference = #"{"suggestions":[{"mailID":"wa_0","kind":"reminder","message":"Review booking","evidenceID":"wa_0:primary"}]}"#
        do { _=try ProactiveRules.decode(waReference,candidates:[candidate],registration:"A",scope:"s",now:.now);fatalError("Mail evidence reference accepted for WhatsApp") } catch {}
        let reply=try EmailReplyDraftRules.decode(#"{"draft":"Thanks for the invitation. [Confirm availability]"}"#);precondition(reply.contains("[Confirm availability]"))
        let hbNow=Date.now
        precondition(!ProactiveRules.heartbeatMailEligible(received:hbNow.addingTimeInterval(-49*3600),now:hbNow))
        precondition(ProactiveRules.heartbeatMailEligible(received:hbNow.addingTimeInterval(-48*3600),now:hbNow))
        precondition(!ProactiveRules.heartbeatMailEligible(received:hbNow.addingTimeInterval(-48*3600-1),now:hbNow))
        precondition(ProactiveRules.heartbeatMailEligible(received:hbNow.addingTimeInterval(-7200),now:hbNow))
        let replyCandidate=DiscoveryCandidate(alias:"wa_reply",mailID:"reply-source",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceChatID:"selected",sourceMessageID:"reply-source",sourceIdentity:"link",sourceRevision:"v1",sourceText:"Could you confirm whether you can join our project meeting?")
        let replyPayload = #"{"suggestions":[{"mailID":"wa_reply","kind":"reply","message":"A project reply would help.","evidence":"Could you confirm whether you can join our project meeting?","draft":"Thanks. [Confirm whether you can attend]."}]}"#
        let localReplies=try ProactiveRules.decode(replyPayload,candidates:[replyCandidate],registration:"account",scope:"scope",now:.now)
        precondition(localReplies[0].replyDraft?.contains("[Confirm") == true && localReplies[0].proposedChange == nil)
        precondition(ProactiveRules.unreported(localReplies,prior:localReplies).isEmpty)
        let savedReply=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(localReplies[0]))
        precondition(savedReply == localReplies[0])
        do {_ = try ProactiveRules.decode(replyPayload.replacingOccurrences(of:"Could you confirm whether you can join our project meeting?",with:"invented quote"),candidates:[replyCandidate],registration:"account",scope:"scope",now:.now);preconditionFailure("Ungrounded reply accepted")} catch {}
        // Retirement archives the suggestion only, retaining exact evidence and source provenance.
        let covered=records[0]
        let coverage=DiscoveryRetirementEvidence(kind:"reminder",id:"existing-reminder",revision:"native-v7")
        let retirementJSON = #"{"suggestions":[],"handled":[],"resolved":[],"retirements":[{"reviewID":"review_0","targetID":"reminder_0","reason":"The existing registration reminder covers this same registration deadline."}]}"#
        _ = try completed(retirementJSON)
        func retire(_ json:String = retirementJSON,_ proposal:PADiscovery = covered,_ target:DiscoveryRetirementEvidence = coverage)throws->[DiscoveryRetirement] {
            try ProactiveRules.decodeRetirements(json,earlier:["review_0":proposal],targets:["reminder_0":target],registration:"A")
        }
        func retirementRejected(_ operation:()throws->Void) {do {try operation();fatalError("Unsupported retirement accepted")} catch {}}
        let retirements=try retire()
        let archived=try ProactiveRules.retiring(retirements,from:[covered],now:hbNow)
        precondition(archived[0].retiredAt == hbNow && archived[0].retirementEvidence == coverage && archived[0].retirementReason == retirements[0].reason)
        precondition(archived[0].reviewState == nil && !archived[0].dismissed && archived[0].mailID == covered.mailID && archived[0].evidence == covered.evidence,"Retirement is not approval, dismissal, source loss or completion")
        let reopenedArchive=try JSONDecoder().decode([PADiscovery].self,from:JSONEncoder().encode(archived));precondition(reopenedArchive == archived)
        let emptyRetirement=try ProactiveRules.decodeRetirements(blank,earlier:[:],targets:[:],registration:"A");precondition(emptyRetirement.isEmpty)
        retirementRejected {_ = try retire(retirementJSON.replacingOccurrences(of:"review_0",with:"unissued"))}
        retirementRejected {_ = try retire(retirementJSON.replacingOccurrences(of:"reminder_0",with:"unissued"))}
        retirementRejected {_ = try ProactiveRules.decodeRetirements(retirementJSON,earlier:["review_0":covered],targets:[:],registration:"A")}
        var unsafe=covered;unsafe.registration="another";retirementRejected {_ = try retire(retirementJSON,unsafe)}
        unsafe=covered;unsafe.reviewState="pending";retirementRejected {_ = try retire(retirementJSON,unsafe)}
        unsafe=covered;unsafe.dismissed=true;retirementRejected {_ = try retire(retirementJSON,unsafe)}
        unsafe=covered;unsafe.supersededBy="replacement";retirementRejected {_ = try retire(retirementJSON,unsafe)}
        retirementRejected {_ = try retire(retirementJSON,archived[0])}
        retirementRejected {_ = try retire(retirementJSON,covered,.init(kind:"event",id:"event",revision:"r"))}
        unsafe=covered;unsafe.kind="remove";retirementRejected {_ = try retire(retirementJSON,unsafe)}
        unsafe=covered;unsafe.kind="projectTask";unsafe.proposedProjectTask = .init(target:project,connection:"Registration work")
        let projectProof=DiscoveryRetirementEvidence(kind:"projectTask",id:"child-task",revision:"task-revision",parentID:project.id.uuidString)
        let projectRetirements=try retire(retirementJSON,unsafe,projectProof);precondition(projectRetirements.count == 1)
        var wrongParent=projectProof;wrongParent.parentID=UUID().uuidString
        retirementRejected {_ = try retire(retirementJSON,unsafe,wrongParent)}
        unsafe=covered;unsafe.reviewState="approved";retirementRejected {_ = try ProactiveRules.retiring(retirements,from:[unsafe],now:hbNow)}
        retirementRejected {_ = try ProactiveRules.retiring(retirements+retirements,from:[covered],now:hbNow)}
        retirementRejected {_ = try ProactiveRules.retiring(retirements,from:[],now:hbNow)}
        diagnostic(.retirements,0,.reason,.missingField) {_ = try completed(#"{"suggestions":[],"handled":[],"resolved":[],"retirements":[{"reviewID":"review_0","targetID":"reminder_0"}]}"#)}
        var unchangedCandidate=compound;unchangedCandidate.mailID=covered.mailID;unchangedCandidate.sourceRevision=covered.sourceRevision;unchangedCandidate.sourceDate=covered.sourceDate ?? covered.created
        precondition(ProactiveRules.replacementAliases(unchangedCandidate,earlier:["review_0":covered],permitted:[covered.id]).isEmpty,"Unchanged source may reconsider/retire but cannot author a newer-source replacement")
        unchangedCandidate.sourceDate=covered.created.addingTimeInterval(60)
        precondition(ProactiveRules.replacementAliases(unchangedCandidate,earlier:["review_0":covered],permitted:[covered.id]) == ["review_0"])
        var localProject=covered;localProject.kind="projectTask"
        precondition(ProactiveRules.replacementAliases(unchangedCandidate,earlier:["review_0":localProject],permitted:[localProject.id]).isEmpty,"Unsupported predecessor kinds cannot enter replacement schema")
        let queuedProposals=(0..<25).map {number -> PADiscovery in var item=covered;item.id="proposal-\(number)";return item}
        let firstBatch=ProactiveRules.reconsiderationBatch(queuedProposals,progress:.init(),context:"c1")
        precondition(firstBatch.count == 12)
        var receipts=ProactiveRules.recordingReconsideration(.init(),reviewed:firstBatch,active:queuedProposals,context:"c1")
        let secondBatch=ProactiveRules.reconsiderationBatch(queuedProposals,progress:receipts,context:"c1")
        precondition(Set(firstBatch.map(\.id)).isDisjoint(with:Set(secondBatch.map(\.id))),"Next cycle gives unreviewed cards priority")
        receipts=ProactiveRules.recordingReconsideration(receipts,reviewed:queuedProposals,active:queuedProposals,context:"c1")
        precondition(queuedProposals.allSatisfy{receipts.reviewedProposalContexts?[$0.id] == "c1"},"No pending reconsideration remains for unchanged context")
        let restoredReceipts=try JSONDecoder().decode(ProactiveProgress.self,from:JSONEncoder().encode(receipts))
        precondition(restoredReceipts.reviewedProposalContexts == receipts.reviewedProposalContexts)
        precondition(queuedProposals.contains{restoredReceipts.reviewedProposalContexts?[$0.id] != "c2"},"New native/source context enables reconsideration")
        let pruned=ProactiveRules.recordingReconsideration(receipts,reviewed:[],active:[],context:"c1")
        precondition(pruned.reviewedProposalContexts?.isEmpty == true)
        // Exact source chronology and persistent replacement chains; no native mutation.
        let target=DiscoveryNativeTarget(kind:"reminder",itemID:"orion",sourceID:"studies",title:"Orion",hasTime:false,writable:true,recurring:false,fingerprint:"native-v1")
        let initialDate=Date(timeIntervalSince1970:1791000000)
        var old=records[0];old.kind="change";old.sourceDate=initialDate;old.proposedChange = .init(target:target,newDate:"2026-10-20",hasTime:false,connection:"Same report",timeZoneID:TimeZone.current.identifier)
        let newSource=DiscoveryCandidate(alias:"wa_new",mailID:"new-revision",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceIdentity:"link",sourceRevision:"v2",sourceText:"Your Orion report deadline is now 22 October 2026.",sourceDate:initialDate.addingTimeInterval(3600))
        let correction = #"{"suggestions":[{"mailID":"wa_new","kind":"change","message":"Your deadline moved to 22 October.","evidence":"Your Orion report deadline is now 22 October 2026.","targetID":"reminder_0","newDate":"2026-10-22","hasTime":false,"connection":"Same Orion report.","replaces":["review_0"],"replacementReason":"A later correction replaces the earlier deadline for the same report."}]}"#
        func parse(_ payload:String,_ prior:PADiscovery=old,_ source:DiscoveryCandidate=newSource)throws->[PADiscovery] {try ProactiveRules.decode(payload,candidates:[source],registration:"A",scope:"s",now:initialDate.addingTimeInterval(7200),targets:["reminder_0":target],earlier:["review_0":prior])}
        func replacementRejected(_ body:()throws->Void) {do {try body();preconditionFailure("Unsafe replacement accepted")} catch {}}
        let corrected=try parse(correction)[0]
        let chain=try ProactiveRules.reconciled([corrected],prior:[old],issued:["review_0":old],now:corrected.created)
        precondition(chain[0].supersededBy == corrected.id && chain[1].replaces == [old.id] && chain[0].proposedChange?.newDate == "2026-10-20")
        let restoredChain=try JSONDecoder().decode([PADiscovery].self,from:JSONEncoder().encode(chain));precondition(restoredChain == chain)
        replacementRejected {_ = try parse(correction.replacingOccurrences(of:"review_0",with:"made-up"))}
        var foreign=old;foreign.registration="B";replacementRejected {_ = try parse(correction,foreign)}
        var pending=old;pending.reviewState="pending";replacementRejected {_ = try parse(correction,pending)}
        var approved=old;approved.reviewState="approved";replacementRejected {_ = try parse(correction,approved)}
        var superseded=old;superseded.supersededBy="newer";replacementRejected {_ = try parse(correction,superseded)}
        var otherPlan=old;otherPlan.proposedChange?.target.itemID="vega";replacementRejected {_ = try parse(correction,otherPlan)}
        var olderSource=newSource;olderSource.sourceDate=initialDate.addingTimeInterval(-1);replacementRejected {_ = try parse(correction,old,olderSource)}
        var raced=old;raced.dismissed=true;replacementRejected {_ = try ProactiveRules.reconciled([corrected],prior:[raced],issued:["review_0":old],now:.now)}
        replacementRejected {_ = try ProactiveRules.reconciled([corrected],prior:[old],issued:["review_0":old],now:.now,permittedEarlier:[])}
        replacementRejected {_ = try ProactiveRules.reconciled([],prior:[raced],issued:["review_0":old],now:.now,permittedEarlier:[old.id])}
        var dependent=corrected;dependent.comparisonSourceIDs=[old.id]
        precondition(ProactiveRules.comparisonEvidenceAvailable(dependent,records:[old],available:{_ in true}))
        precondition(!ProactiveRules.comparisonEvidenceAvailable(dependent,records:[old],available:{_ in false}))
        precondition(!ProactiveRules.comparisonEvidenceAvailable(dependent,records:[],available:{_ in true}))
        precondition(!ProactiveRules.comparisonEvidenceAvailable(dependent,records:[foreign],available:{_ in true}))
        var cancellationSource=newSource;cancellationSource.mailID="cancellation";cancellationSource.sourceText="Your Orion report submission is cancelled.";cancellationSource.sourceDate=corrected.created.addingTimeInterval(3600)
        let cancellation = #"{"suggestions":[{"mailID":"wa_new","kind":"update","message":"Your Orion submission is cancelled; check the existing reminder when convenient.","evidence":"Your Orion report submission is cancelled.","replaces":["review_0"],"replacementReason":"The tutor cancelled the same Orion submission."}]}"#
        let cancelled=try parse(cancellation,corrected,cancellationSource)[0]
        var cancelledChain=try ProactiveRules.reconciled([cancelled],prior:chain,issued:["review_0":corrected],now:cancelled.created)
        precondition(cancelledChain.last?.proposedChange == nil && cancelledChain.filter{$0.supersededBy == nil}.map(\.id) == [cancelled.id])
        cancelledChain[2].dismissed=true
        precondition(cancelledChain[0].supersededBy != nil && cancelledChain[1].supersededBy != nil,"Dismissing the cancellation cannot revive obsolete advice")
        let staleTurn=AssistantTurn(role:"assistant",content:old.message,completed:true,deliveryID:old.deliveryID)
        precondition(ProactiveReviewRules.reference("yes",turns:[staleTurn],records:cancelledChain) == nil)
        var legacyAck=dismissed;legacyAck.id="legacy-ack";legacyAck.sourceKind=nil
        var sameSource=legacyAck;sameSource.id="sibling-ack"
        var otherOwner=legacyAck;otherOwner.registration="other"
        var retired=legacyAck;retired.supersededBy="replacement"
        var notDismissed=legacyAck;notDismissed.dismissed=false
        var waAck=legacyAck;waAck.id="wa-first";waAck.sourceKind="whatsapp";waAck.sourceChatID="a:b";waAck.sourceMessageID="c"
        var anotherChat=waAck;anotherChat.id="wa-second";anotherChat.sourceChatID="a";anotherChat.sourceMessageID="b:c"
        let unrelatedAcknowledgements=(0..<2000).map {n -> PADiscovery in var value=legacyAck;value.id="unrelated-\(n)";value.mailID="unrelated-mail-\(n)";return value}
        let index=ReviewAcknowledgementIndex(unrelatedAcknowledgements+[legacyAck,sameSource,sameSource,otherOwner,retired,notDismissed,waAck,anotherChat],registration:legacyAck.registration)
        precondition(index.mail[legacyAck.mailID]?.map(\.id) == [legacyAck.id,sameSource.id,sameSource.id],"Exact-source lookup preserves legacy mail, sibling order and duplicates while excluding retired/other-owner/undismissed records")
        precondition(index.whatsapp[.init(chat:"a:b",message:"c")]?.map(\.id) == [waAck.id] && index.whatsapp[.init(chat:"a",message:"b:c")]?.map(\.id) == [anotherChat.id],"Chat and message identity must remain separate typed keys")
        precondition(index.mail["missing"] == nil && index.whatsapp[.init(chat:"other",message:"c")] == nil)
        let pageVersions=["memory:fact-one":"version-one","project:space-one":"version-two","page:purpose-one":"version-three"]
        let pageJSON=#"{"pages":[{"id":"project-page","markdown":"Current robotics purpose"}],"workingChanges":[{"id":"project:space-one","text":"Bench validation is next"}],"directory":[{"title":"Unrelated life area"}],"directoryCount":9}"#
        let payload=AutomaticMemoryCapture.pagePayload(pageJSON)
        precondition(!payload.contains("Unrelated life area") && !payload.contains("directory") && payload.contains("Current robotics purpose"))
        let captured=AutomaticMemoryCapture(records:[],dependencies:[],eligibleCount:0,pageContext:payload,contextPageDependencies:pageVersions)
        precondition(captured == captured,"Automatic page captures contain no validation closures or other non-data fields")
        let input=try JSONSerialization.jsonObject(with:Data(captured.context.utf8)) as! [String:Any]
        precondition(input["contextPages"] is [String:Any])
        let unsupplied=AutomaticMemoryCapture(records:[],dependencies:[],eligibleCount:0,pageContext:payload)
        let noPages=try JSONSerialization.jsonObject(with:Data(unsupplied.context.utf8)) as! [String:Any]
        precondition(noPages["contextPages"] == nil,"Unreferenced page prose never enters automatic input")
        let policyCapture=ReviewPolicyCapture(registration:legacyAck.registration,revision:"human-policy-v2",text:"Prioritise current robotics responsibilities.",isDefault:false)
        var pageAdvice=legacyAck;pageAdvice.contextPageDependencies=pageVersions;pageAdvice.reviewPolicy = .init(policyCapture)
        pageAdvice.retirementEvidence = .init(kind:"reminder",id:"exact-reminder",revision:"native-v1",contextPageDependencies:pageVersions,reviewPolicy:.init(policyCapture))
        let reopenedAdvice=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(pageAdvice))
        precondition(reopenedAdvice.contextPageDependencies == pageVersions && reopenedAdvice.reviewPolicy?.matches(policyCapture) == true)
        precondition(reopenedAdvice.retirementEvidence?.contextPageDependencies == pageVersions && reopenedAdvice.retirementEvidence?.reviewPolicy?.matches(policyCapture) == true,"Retirement context stays separate from original proposal support")
        var legacyObject=try JSONSerialization.jsonObject(with:JSONEncoder().encode(pageAdvice)) as! [String:Any]
        legacyObject.removeValue(forKey:"contextPageDependencies");legacyObject.removeValue(forKey:"reviewPolicy")
        let legacyAdvice=try JSONDecoder().decode(PADiscovery.self,from:JSONSerialization.data(withJSONObject:legacyObject))
        precondition(legacyAdvice.contextPageDependencies == nil && legacyAdvice.reviewPolicy == nil && legacyAdvice.message == pageAdvice.message)
        let projected=ProactiveRules.reviewProjection(pageAdvice)
        precondition(projected.id == pageAdvice.id && projected.contextPageDependencies == pageVersions,"Prepared projection preserves exact stored provenance without rebuilding pages")
        print("PASS automatic page capture: purpose payload, no directory/unreferenced prose, data-only equality, persisted advice/policy receipts and legacy prepared projection")
        print("PASS typed review transport, safe field diagnostics, 32000-byte boundary and proactive rules: grounded aliases/quotes, prohibited kinds, account dedup/dismissal, daily budget, pause/cooldown/persistence and conservative current-thread latest-suggestion review references.")
    }
}
