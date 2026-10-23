import Foundation

enum ReviewMailDedupChecks {
    static func run() throws {
        let now=Date.now
        let source=DiscoveryCandidate(alias:"mail_0",mailID:"fictional-mail",evidence:"Submit the Orion report on 21 October 2026.",followUpEvidence:"",sourceRevision:"header",sourceAssessmentRevision:"assessment",sourceContentVersion:"account-mail-body-v1")
        let parent=DiscoveryProjectTarget(id:UUID(),revision:UUID(),title:"Orion")
        var original=PADiscovery(id:"original",registration:"owner",mailID:source.mailID,kind:"projectTask",message:"Prepare this task?",evidence:source.evidence,created:now,scope:"scope",sourceRevision:source.sourceRevision,sourceAssessmentRevision:source.sourceAssessmentRevision,proposedDate:.init(start:"2026-10-21",hasTime:false,timeZoneID:TimeZone.current.identifier),proposedProjectTask:.init(target:parent,connection:"Orion report"),sourceContentVersion:source.sourceContentVersion)
        let prepared=ProactiveRules.recordingPreparedMail(.init(),candidates:[source],proposals:[original],failedSources:[],limited:false)
        precondition(prepared.preparedMailVersions == [source.sourceContentVersion!])
        var rewritten=original;rewritten.id="rewritten";rewritten.message="Different generated wording";rewritten.evidence="the Orion report";rewritten.sourceTitle="New generated title";rewritten.sourceAssessmentRevision="new-assessment"
        precondition(ProactiveRules.unreported([rewritten],prior:[original],preparedMailVersions:prepared.preparedMailVersions!).isEmpty,"Same exact email cannot generate another set under rewritten wording/quotes")
        var replacement=rewritten;replacement.kind="remove";replacement.replaces=[original.id]
        precondition(ProactiveRules.unreported([replacement],prior:[original],preparedMailVersions:prepared.preparedMailVersions!).count == 1,"An independently validated replacement can update an existing concern")
        var changedContent=rewritten;changedContent.sourceContentVersion="account-mail-body-v2"
        precondition(ProactiveRules.unreported([changedContent],prior:[original],preparedMailVersions:prepared.preparedMailVersions!).count == 1,"Changed source content remains eligible")
        var unchangedAction=original;unchangedAction.sourceContentVersion=changedContent.sourceContentVersion
        precondition(ProactiveRules.unreported([unchangedAction],prior:[original]).isEmpty,"Changed body cannot replay an unchanged concrete action")
        var otherEmail=rewritten;otherEmail.mailID="another-message";otherEmail.sourceContentVersion="account-othermail-body-v1"
        precondition(ProactiveRules.unreported([otherEmail],prior:[original],preparedMailVersions:prepared.preparedMailVersions!).count == 1,"A separate email with the same topic remains eligible")
        var otherAccount=rewritten;otherAccount.sourceContentVersion="otheraccount-mail-body-v1"
        precondition(ProactiveRules.unreported([otherAccount],prior:[original],preparedMailVersions:prepared.preparedMailVersions!).count == 1,"Mail account belongs to exact content identity")
        let reopened=try JSONDecoder().decode(ProactiveProgress.self,from:JSONEncoder().encode(prepared))
        var nextDay=reopened;nextDay.day="2026-10-22";nextDay.sourceContextRevision="changed-native-context"
        let refreshed=ProactiveRules.completing(nextDay,versions:[:],context:"another-context",limited:false,reportedKeys:[])
        precondition(refreshed.preparedMailVersions == prepared.preparedMailVersions,"Reopen, day and changing context retain durable source receipts")
        let partial=ProactiveRules.recordingPreparedMail(.init(),candidates:[source],proposals:[original],failedSources:[],limited:true)
        precondition(partial.preparedMailVersions == nil,"A capped raw result cannot freeze missing sibling actions")
        let failed=ProactiveRules.recordingPreparedMail(.init(),candidates:[source],proposals:[original],failedSources:[source.alias],limited:false)
        precondition(failed.preparedMailVersions == nil,"Rejected/conflicting source rows stay resumable")
        precondition(ProactiveRules.recordingPreparedMail(.init(),candidates:[source],proposals:[original],failedSources:["unissued-source"],limited:false).preparedMailVersions == nil,"An unattributed rejected row cannot prove complete source preparation")
        precondition(ProactiveRules.recordingPreparedMail(prepared,candidates:[source],proposals:[],failedSources:[],limited:false).preparedMailVersions == prepared.preparedMailVersions,"Reconsideration-only runs preserve existing receipts")
        precondition(ProactiveRules.recordingPreparedMail(.init(),candidates:[source],proposals:[],failedSources:[],limited:false).preparedMailVersions == nil,"No proposal means no already-prepared item")
        var sibling=original;sibling.id="calendar";sibling.kind="calendar";sibling.proposedProjectTask=nil
        precondition(ProactiveRules.unreported([original,sibling],prior:[]).count == 2,"Initial Calendar and project-task destinations remain separate")
        var named=original;named.sourceTitle="First distinct action"
        var second=named;second.id="second";second.sourceTitle="Second distinct action"
        precondition(ProactiveRules.unreported([named,second],prior:[]).count == 2,"A broad quote can support separately titled actions")
        var legacyProgress=ProactiveProgress();legacyProgress.assessedSourceVersions=[ProactiveRules.sourceKey("mail",source.mailID):source.sourceAssessmentRevision!]
        let recovered=ProactiveRules.recoveringPreparedMail(legacyProgress,candidates:[source],prior:[original],registration:original.registration)
        precondition(recovered.preparedMailVersions == prepared.preparedMailVersions,"A completed exact legacy pass recovers a receipt without matching old context")
        precondition(ProactiveRules.recoveringPreparedMail(.init(),candidates:[source],prior:[original],registration:original.registration).preparedMailVersions == nil,"A legacy proposal alone cannot freeze missing siblings")
        let unknownFailure=ProactiveRules.completing(.init(),versions:legacyProgress.assessedSourceVersions!,context:"failed-context",limited:false,reportedKeys:[],sourceFailuresAttributed:false)
        precondition(ProactiveRules.recoveringPreparedMail(unknownFailure,candidates:[source],prior:[original],registration:original.registration).preparedMailVersions == nil,"An unattributed rejection cannot later migrate into a completed preparation receipt")
        precondition(ProactiveRules.recoveringPreparedMail(legacyProgress,candidates:[source],prior:[original],registration:"other-owner").preparedMailVersions == nil,"Legacy recovery respects account ownership")
        var parentEdited=original;parentEdited.id="parent-edited";parentEdited.sourceAssessmentRevision="new-assessment";parentEdited.proposedProjectTask?.target.revision=UUID();parentEdited.proposedProjectTask?.target.title="Renamed Orion"
        precondition(ProactiveRules.unreported([parentEdited],prior:[original]).isEmpty,"Parent metadata/revision cannot give the same task a new identity")
        parentEdited.proposedProjectTask?.target.id=UUID()
        precondition(ProactiveRules.unreported([parentEdited],prior:[original]).count == 1,"Distinct destinations are not merged within partial preparation")
        for outcome in ["approved","pending","dismissed","retired","superseded"] {
            var old=original;old.sourceContentVersion=nil
            switch outcome {
            case "dismissed":old.dismissed=true
            case "retired":old.retiredAt=now
            case "superseded":old.supersededBy="later"
            default:old.reviewState=outcome
            }
            var new=old;new.id="new";new.sourceAssessmentRevision="new-assessment"
            precondition(ProactiveRules.unreported([new],prior:[old]).isEmpty,"Legacy outcome survives regenerated assessment: "+outcome)
        }
        original.sourceContentVersion=nil
        let legacy=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(original))
        precondition(legacy == original,"Additive metadata preserves legacy records")
        var whatsapp=rewritten;whatsapp.sourceKind="whatsapp";whatsapp.sourceChatID="chat";whatsapp.sourceIdentity="link"
        precondition(ProactiveRules.unreported([whatsapp],prior:[],preparedMailVersions:prepared.preparedMailVersions!).count == 1,"Mail receipts cannot suppress WhatsApp")
        print("PASS durable Review Mail preparation, content identity, partial-result, legacy outcome and sibling-destination checks")
    }
}
