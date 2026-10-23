#if DEBUG
import Foundation

/// Actual saved-proposal authority and project persistence, using disposable app storage.
@MainActor enum PreparedApprovalEvaluation {
    static func run() throws -> [String:Bool] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") else {throw IntegrationError.verification}
        let arguments=UserDefaults.standard.volatileDomain(forName:UserDefaults.argumentDomain)
        var fixtureArguments=arguments;fixtureArguments["assistantContextEnabled"]=true;fixtureArguments["automaticEmailSummaries"]=true
        UserDefaults.standard.setVolatileDomain(fixtureArguments,forName:UserDefaults.argumentDomain)
        defer {UserDefaults.standard.setVolatileDomain(arguments,forName:UserDefaults.argumentDomain)}
        let model=DashboardModel(),original=try ReviewInboxEvaluation.seed(model)
        var record=original;record.kind="reminder";record.proposedChange=nil;record.sourceTitle="Submit Orion report"
        try model.proactive.seedAdviceFixture([record],model:model)
        record=model.proactive.state.records[0]
        var checks:[String:Bool]=[:]
        model.reviewDiscovery(record)
        if case .create(let request)=model.editTarget {
            checks["native form captures exact displayed proposal"]=request.discoveryApproval == model.preparedApprovalSnapshot(record) && request.id.uuidString == record.id
        } else {checks["native form captures exact displayed proposal"]=false}
        let snapshot=model.preparedApprovalSnapshot(record)
        let fact=PAMemory(registration:model.chatGPT.activeID,text:"The fictional report is for a different supervisor now.",kind:.context,provenance:"Fictional human",evidence:"The fictional report is for a different supervisor now.")
        guard model.assistant.memory.put(fact) else {throw SummaryFailure.invalid}
        var summary=model.emailSummaries.records[0];summary.bodyFingerprint="changed-after-preparation"
        try model.emailSummaries.seedAdviceFixture([summary])
        model.mailData = .init(messages:[],accounts:model.mailData.accounts,errors:[])
        try model.validatePreparedApproval(record)
        checks["changed memory and source body do not block a concrete approval"]=model.preparedApprovalSnapshot(record) == snapshot && model.currentPreparedApproval(record)
        var changed=record;changed.sourceTitle="Different action"
        try model.proactive.seedAdviceFixture([changed],model:model)
        checks["changed displayed payload rejects the old approval"] = !model.currentPreparedApproval(record)
        try model.proactive.seedAdviceFixture([record],model:model)
        var wrongAccount=record;wrongAccount.registration="another-registration"
        checks["approval cannot cross account"] = !model.currentPreparedApproval(wrongAccount)
        try model.proactive.beginReview(record.id,model:model)
        checks["pending receipt blocks a second review but preserves in-flight validity"] = !model.proactive.canReview(record.id,model:model) && model.currentPreparedApproval(record)
        try model.proactive.abortReview(record.id,registration:record.registration)
        try model.proactive.beginReview(record.id,model:model);try model.proactive.finishReview(record.id,registration:record.registration)
        checks["completed receipt prevents replay"] = !model.currentPreparedApproval(record) && !model.proactive.canReview(record.id,model:model)

        var parent=LifeItem(registration:record.registration,kind:.space,title:"Fictional engineering project")
        parent=try model.assistant.projects.save(parent,expected:nil)
        var proposal=record;proposal.id=UUID().uuidString;proposal.kind="projectTask"
        proposal.proposedProjectTask = .init(target:.init(id:parent.id,revision:parent.revision,title:parent.title),connection:"Existing project")
        try model.proactive.seedAdviceFixture([proposal],model:model)
        var revised=parent;revised.notes="A corrected project description"
        revised=try model.assistant.projects.save(revised,expected:parent.revision)
        let item=LifeItem(registration:record.registration,kind:.task,title:"Submit fictional report",parentID:parent.id,notes:record.evidence)
        try model.savePreparedProjectItem(item,proposal:proposal)
        checks["project description revision does not block task approval"]=model.assistant.projects.items(record.registration,includeTopics:true).contains{$0.id == item.id && $0.parentID == parent.id}
        do {try model.savePreparedProjectItem(item,proposal:proposal);checks["project receipt prevents approval replay"]=false}
        catch {checks["project receipt prevents approval replay"]=true}
        var unavailable=proposal;unavailable.id=UUID().uuidString
        try model.proactive.seedAdviceFixture([unavailable],model:model)
        var invalidDestination=item;invalidDestination.id=UUID();invalidDestination.title="Second fictional report";invalidDestination.parentID=UUID()
        do {try model.savePreparedProjectItem(invalidDestination,proposal:unavailable);checks["missing exact project destination blocks creation"]=false}
        catch {checks["missing exact project destination blocks creation"]=true}
        var archived=revised;archived.status = .archived
        _ = try model.assistant.projects.save(archived,expected:revised.revision)
        invalidDestination.parentID=parent.id
        do {try model.savePreparedProjectItem(invalidDestination,proposal:unavailable);checks["archived project destination blocks creation"]=false}
        catch {checks["archived project destination blocks creation"]=true}
        checks["project failures leave no task and no receipt"] = !model.assistant.projects.items(record.registration,includeTopics:true).contains{$0.id == invalidDestination.id} && model.assistant.projects.receipt("project-suggestion:"+unavailable.id,registration:record.registration) == nil
        // Historical proposals remain eligible for retirement after source/context
        // revisions, while automatic reuse of that old advice stays unavailable.
        var historical=record;historical.id=UUID().uuidString;historical.sourceTitle="Reach out Riah"
        historical.message="Contact Ria about the fictional winery tasting. An earlier spelling was uncertain."
        historical.reviewState=nil;historical.reviewedAt=nil
        try model.proactive.seedAdviceFixture([historical],model:model)
        historical=model.proactive.state.records[0]
        checks["changed old interpretation is withheld from new advice"] = !model.proactive.reviewEvidenceAvailable(historical.id,model:model)
        checks["historical card still reaches heartbeat reconsideration"] = model.proactive.earlierCandidates(model,mailReview:nil,whatsappReady:false).contains(historical)
        let renamed=TaskItem(id:"fictional-ria",listID:"fictional-list",title:"Reach out Ria",due:nil,hasTime:false,sourceLabel:"Fictional",writable:true,recurring:false,modified:.now)
        let reminders=ReminderSnapshot(sources:[],reminders:[renamed]);model.reminderData=reminders
        let issued:[String:PADiscovery]=["review_0":historical]
        let proof=DiscoveryRetirementEvidence(kind:"reminder",id:renamed.id,revision:DiscoveryNativeTarget.reminder(renamed).fingerprint)
        let json=#"{"suggestions":[],"handled":[],"resolved":[],"retirements":[{"reviewID":"review_0","targetID":"reminder_0","reason":"The corrected contact action covers this request."}]}"#
        let mixed=#"{"suggestions":[],"handled":[{"mailID":"mail_0","targetID":"unissued","reason":"Unsupported association","requestEvidenceID":"mail_0:primary","allActionsAddressed":true}],"resolved":[],"retirements":[{"reviewID":"review_0","targetID":"reminder_0","reason":"The corrected contact action covers this request."}]}"#
        let rejectedAssociation=try ProactiveResultRules.validatedRows(mixed,section:.handled) {try EmailReviewRules.decodeHandled($0,summaries:[:],targets:[:],now:.now)}
        let preservedRetirement=try ProactiveResultRules.validatedRows(mixed,section:.retirements) {try ProactiveRules.decodeRetirements($0,earlier:issued,targets:["reminder_0":proof],registration:record.registration)}
        checks["unsupported handled association preserves verified retirement"] = rejectedAssociation.values.isEmpty && rejectedAssociation.issues.count == 1 && preservedRetirement.values.count == 1
        let retirements=try ProactiveRules.decodeRetirements(json,earlier:issued,targets:["reminder_0":proof],registration:record.registration)
        var diagnosticProgress=ProactiveProgress();diagnosticProgress.validationEntries=rejectedAssociation.entries;diagnosticProgress.validationRunID="fixture-run"
        try model.proactive.commitComparison([],issued:issued,permittedEarlier:[],registration:record.registration,progress:diagnosticProgress,now:.now,retirements:retirements,permittedRetirements:[historical.id])
        checks["diagnostic details are bound to the exact run"] = model.proactive.validationNotice(record.registration,runID:"fixture-run")?.contains("Reason:") == true && model.proactive.validationNotice(record.registration,runID:"later-run") == nil
        let retired=model.proactive.state.records[0]
        checks["retirement saves exact native coverage without reviving old advice"] = retired.retirementEvidence == proof && retired.retiredAt != nil && !model.proactive.canReview(retired.id,model:model)
        checks["retirement leaves native reminder unchanged"] = EmailNativeEvidence.hash(model.reminderData) == EmailNativeEvidence.hash(reminders)
        model.proactive.restoreRetired(retired,model:model)
        historical=model.proactive.state.records[0]
        checks["human can restore retired historical suggestion"] = historical.retiredAt == nil && model.proactive.canReview(historical.id,model:model)
        let exclusions=model.assistant.excludedAccounts
        let sourceKeys=["aiExcludedAccounts","aiExcludedCalendars","aiExcludedLists"]
        let savedChoices=sourceKeys.map{UserDefaults.standard.object(forKey:$0)}
        if let account=model.emailSummaries.records.first?.message?.accountID {model.assistant.excludedAccounts.insert(account)}
        checks["revoked source prevents historical reconsideration"] = model.proactive.earlierCandidates(model,mailReview:nil,whatsappReady:false).isEmpty
        model.assistant.excludedAccounts=exclusions
        for (key,value) in zip(sourceKeys,savedChoices) {if let value {UserDefaults.standard.set(value,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}}
        let exact=historical;model.proactive.dismiss(historical,model:model)
        do {try model.proactive.commitComparison([],issued:["review_0":exact],permittedEarlier:[],registration:record.registration,progress:.init(),now:.now,retirements:retirements,permittedRetirements:[historical.id]);checks["dismissal race rejects historical retirement"]=false}
        catch {checks["dismissal race rejects historical retirement"]=true}
        return checks
    }
}
#endif
