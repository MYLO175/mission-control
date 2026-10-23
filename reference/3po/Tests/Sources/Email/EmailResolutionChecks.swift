import Foundation

@main struct EmailResolutionChecks {
    static func main() throws {
        var checks=0
        func check(_ value:Bool,_ explanation:String) {
            precondition(value,explanation);checks += 1
        }
        let formatter=ISO8601DateFormatter()
        let requestDate=formatter.date(from:"2026-10-07T09:00:00Z")!
        let confirmationDate=formatter.date(from:"2026-10-08T10:00:00Z")!
        let now=confirmationDate.addingTimeInterval(3600)
        func message(_ number:Int,accountID:String="fictional-provider",received:Date,subject:String="Orion graduate engineering assessment",replied:Bool=false,sender:String="Orion recruitment <recruitment@example.invalid>",id:String?=nil)throws->MailMessage {
            let value:[String:Any]=["id":id ?? accountID+":"+String(number),"accountID":accountID,"account":"Fictional account","messageID":number,
                "internetMessageID":"fictional-\(number)@example.invalid","sender":sender,"subject":subject,"received":formatter.string(from:received),
                "unread":true,"replied":replied,"flagged":false]
            return try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:value))
        }
        let original=try message(1,received:requestDate)
        let later=try message(2,received:confirmationDate)
        let requestQuote="Complete the Orion graduate engineering assessment by 20 October 2026."
        let confirmationQuote="Your Orion graduate engineering assessment was submitted successfully."
        func assessment(_ source:MailMessage,quote:String,attention:Bool)->EmailSummary {
            EmailSummary(id:source.id,registration:"fictional-registration",fingerprint:EmailSummary.fingerprint(source),summary:quote,attention:attention,
                reason:attention ? "Complete the requested assessment." : "The submission was confirmed.",evidence:quote,
                bodyFingerprint:EmailSummary.fingerprintBody(quote),messageReceived:source.received,message:source,worthReading:false,needsReply:false,replyChannel:"external")
        }
        let request=assessment(original,quote:requestQuote,attention:true)
        let confirmation=assessment(later,quote:confirmationQuote,attention:false)
        let requestAlias="mail_0",confirmationAlias="confirmation_0"
        let row:[String:Any]=["mailID":requestAlias,"confirmationID":confirmationAlias,
            "requestEvidenceID":requestAlias+":primary","confirmationEvidenceID":confirmationAlias+":primary","allActionsAddressed":true,
            "reason":"The later receipt confirms submission of the same Orion graduate engineering assessment requested in the earlier email."]
        func response(_ rows:[[String:Any]])throws->String {
            String(decoding:try JSONSerialization.data(withJSONObject:["resolved":rows]),as:UTF8.self)
        }
        let validJSON=try response([row])
        func decode(_ text:String,requests:[String:EmailSummary]?=nil,confirmations:[String:EmailSummary]?=nil)throws->[(String,EmailResolution)] {
            try EmailResolutionRules.decode(text,requests:requests ?? [requestAlias:request],confirmations:confirmations ?? [confirmationAlias:confirmation],now:now)
        }
        func reject(_ text:String,requests:[String:EmailSummary]?=nil,confirmations:[String:EmailSummary]?=nil) {
            do {_=try decode(text,requests:requests,confirmations:confirmations);preconditionFailure("Unsupported resolution accepted")}
            catch {checks += 1}
        }
        func rejectRow(_ field:String,_ value:Any)throws {
            var changed=row;changed[field]=value;reject(try response([changed]))
        }
        func matches(_ receipt:EmailResolution,requestMessage:MailMessage?=nil,requestSummary:EmailSummary?=nil,confirmationMessage:MailMessage?=nil,confirmationSummary:EmailSummary?=nil)->Bool {
            EmailResolutionRules.matches(receipt,request:requestMessage ?? original,summary:requestSummary ?? request,
                confirmation:confirmationMessage ?? later,confirmationSummary:confirmationSummary ?? confirmation)
        }

        let decoded=try decode(validJSON)
        check(decoded.count == 1 && decoded[0].0 == original.id,"Only the issued request identity is returned")
        let receipt=decoded[0].1
        check(receipt.requestVersion == EmailSummary.sourceVersion(original,request) && receipt.assessmentRevision == request.adviceRevision(replied:false),"The original source and assessment are captured separately")
        check(receipt.requestQuote == requestQuote && receipt.confirmation.quote == confirmationQuote,"Quotes come from the validated assessments")
        check(receipt.confirmation.messageID == later.id && receipt.confirmation.accountID == later.accountID && receipt.confirmation.sourceVersion == EmailSummary.sourceVersion(later,confirmation),"Exact confirmation identity, account and source version are captured")
        check(receipt.confirmation.assessmentRevision == confirmation.adviceRevision(replied:false) && receipt.created == now,"The confirming assessment and creation time are captured")
        check(matches(receipt),"An unchanged receipt is usable")
        check(try JSONDecoder().decode(EmailResolution.self,from:JSONEncoder().encode(receipt)) == receipt,"Resolution persistence is lossless")
        var dependencies=receipt
        dependencies.memoryDependencies=[.init(id:"fictional-memory",fingerprint:"memory-version")]
        dependencies.whatsappDependencies=[.init(chatID:"fictional-chat",linkedIdentity:"fictional-device",fingerprint:"window-version")]
        dependencies.memoryUse = .heartbeatSuggestions
        dependencies.contextPageDependencies=["project:fictional-project":"exact-project-version"]
        dependencies.reviewPolicy = .init(ReviewPolicyCapture(registration:request.registration,revision:"policy-v1",text:"Prefer genuine personal requests.",isDefault:false))
        check(try JSONDecoder().decode(EmailResolution.self,from:JSONEncoder().encode(dependencies)) == dependencies,"Optional dependency receipts persist")
        check(receipt.contextPageDependencies == nil && receipt.reviewPolicy == nil,"Legacy resolution has no invented page/policy dependency")
        check(try decode("{}").isEmpty,"Legacy comparison output can omit resolved")
        check(try decode(#"{"resolved":null}"#).isEmpty,"Null resolved means no resolution")
        check(try decode(#"{"suggestions":[],"handled":[],"resolved":[]}"#).isEmpty,"Resolution coexists with other comparison output")

        try rejectRow("mailID","invented")
        try rejectRow("confirmationID","invented")
        try rejectRow("requestEvidenceID","mail_1:primary")
        try rejectRow("requestEvidenceID",requestAlias+":followup")
        try rejectRow("confirmationEvidenceID",requestAlias+":primary")
        try rejectRow("confirmationEvidenceID",confirmationAlias+":followup")
        try rejectRow("scope","occurrence")
        try rejectRow("targetID","event_0")
        try rejectRow("evidence","Invented quote")
        try rejectRow("reason","")
        try rejectRow("reason"," \n ")
        try rejectRow("reason",String(repeating:"x",count:501))
        try rejectRow("allActionsAddressed",false) // A partial outcome cannot withdraw the whole request.
        try rejectRow("allActionsAddressed",NSNull())
        var omitted=row;omitted.removeValue(forKey:"allActionsAddressed");reject(try response([omitted]))
        reject(try response([row,row]))
        var aliasDuplicate=row;aliasDuplicate["mailID"]="mail_1";aliasDuplicate["requestEvidenceID"]="mail_1:primary"
        reject(try response([row,aliasDuplicate]),requests:[requestAlias:request,"mail_1":request])
        var manyRequests:[String:EmailSummary]=[:],manyRows:[[String:Any]]=[]
        for index in 0..<13 {
            let source=try message(100+index,received:requestDate)
            let alias="mail_\(index)";manyRequests[alias]=assessment(source,quote:requestQuote,attention:true)
            var entry=row;entry["mailID"]=alias;entry["requestEvidenceID"]=alias+":primary";manyRows.append(entry)
        }
        check(try decode(response(Array(manyRows.prefix(12))),requests:manyRequests).count == 12,"Twelve distinct requests fit the bounded response")
        reject(try response(manyRows),requests:manyRequests)

        var changedRequest=request;changedRequest.keepInReview=true
        reject(validJSON,requests:[requestAlias:changedRequest])
        check(!matches(receipt,requestSummary:changedRequest),"Keep in review invalidates an inferred resolution immediately")
        changedRequest.keepInReview=false
        check(matches(receipt,requestSummary:changedRequest),"Removing the override restores an otherwise exact receipt")
        changedRequest=request;changedRequest.needsReply=true;changedRequest.replyChannel="email"
        reject(validJSON,requests:[requestAlias:changedRequest])
        check(!matches(receipt,requestSummary:changedRequest),"An outstanding email reply cannot be hidden by submission evidence")
        changedRequest=request;changedRequest.attention=false
        reject(validJSON,requests:[requestAlias:changedRequest])
        changedRequest.followUpDate="2026-10-20"
        check(try decode(validJSON,requests:[requestAlias:changedRequest]).count == 1,"A future action date also makes an original request eligible")
        changedRequest=request;changedRequest.message=nil
        reject(validJSON,requests:[requestAlias:changedRequest])
        var changedConfirmation=confirmation;changedConfirmation.message=nil
        reject(validJSON,confirmations:[confirmationAlias:changedConfirmation])
        changedRequest=request;changedRequest.id="wrong-request"
        reject(validJSON,requests:[requestAlias:changedRequest])
        changedConfirmation=confirmation;changedConfirmation.id="wrong-confirmation"
        reject(validJSON,confirmations:[confirmationAlias:changedConfirmation])
        changedConfirmation=confirmation;changedConfirmation.registration="other-registration"
        reject(validJSON,confirmations:[confirmationAlias:changedConfirmation])
        check(!matches(receipt,confirmationSummary:changedConfirmation),"Assessments from another registration cannot support the receipt")
        let foreign=try message(2,accountID:"other-provider",received:confirmationDate)
        let foreignAssessment=assessment(foreign,quote:confirmationQuote,attention:false)
        reject(validJSON,confirmations:[confirmationAlias:foreignAssessment])
        check(!matches(receipt,confirmationMessage:foreign,confirmationSummary:foreignAssessment),"Confirmation evidence cannot cross Mail accounts")
        for date in [requestDate,requestDate.addingTimeInterval(-1)] {
            let early=try message(2,received:date)
            let earlyAssessment=assessment(early,quote:confirmationQuote,attention:false)
            reject(validJSON,confirmations:[confirmationAlias:earlyAssessment])
            check(!matches(receipt,confirmationMessage:early,confirmationSummary:earlyAssessment),"A confirmation must be strictly later")
        }
        let sameID=try message(2,received:confirmationDate,id:original.id)
        reject(validJSON,confirmations:[confirmationAlias:assessment(sameID,quote:confirmationQuote,attention:false)])
        changedRequest=request;changedRequest.fingerprint="stale-request"
        reject(validJSON,requests:[requestAlias:changedRequest])
        check(!matches(receipt,requestSummary:changedRequest),"A stale request header fingerprint is unusable")
        changedConfirmation=confirmation;changedConfirmation.fingerprint="stale-confirmation"
        reject(validJSON,confirmations:[confirmationAlias:changedConfirmation])
        check(!matches(receipt,confirmationSummary:changedConfirmation),"A stale confirmation header fingerprint is unusable")
        changedRequest=request;changedRequest.evidence=""
        reject(validJSON,requests:[requestAlias:changedRequest])
        changedConfirmation=confirmation;changedConfirmation.evidence=""
        reject(validJSON,confirmations:[confirmationAlias:changedConfirmation])
        changedConfirmation.evidence=String(repeating:"x",count:501)
        reject(validJSON,confirmations:[confirmationAlias:changedConfirmation])

        var corrupted=receipt;corrupted.requestVersion="different-source"
        check(!matches(corrupted),"The exact request source version is required")
        corrupted=receipt;corrupted.assessmentRevision="different-assessment"
        check(!matches(corrupted),"The exact request assessment is required")
        corrupted=receipt;corrupted.requestQuote="Different action"
        check(!matches(corrupted),"The captured request quote cannot change")
        corrupted=receipt;corrupted.confirmation.messageID="different-id"
        check(!matches(corrupted),"The exact confirming email identity is required")
        corrupted=receipt;corrupted.confirmation.accountID="different-account"
        check(!matches(corrupted),"The captured confirmation account cannot change")
        corrupted=receipt;corrupted.confirmation.sourceVersion="different-source"
        check(!matches(corrupted),"The exact confirmation content version is required")
        corrupted=receipt;corrupted.confirmation.assessmentRevision="different-assessment"
        check(!matches(corrupted),"The exact confirming assessment is required")
        corrupted=receipt;corrupted.confirmation.quote="Different outcome"
        check(!matches(corrupted),"The captured confirmation quote cannot change")
        corrupted=receipt;corrupted.reason=""
        check(!matches(corrupted),"An invalid saved receipt explanation is unusable")
        changedRequest=request;changedRequest.reason="A changed assessment interpretation."
        check(!matches(receipt,requestSummary:changedRequest),"A changed request assessment withdraws the old receipt")
        changedConfirmation=confirmation;changedConfirmation.reason="A changed confirmation interpretation."
        check(!matches(receipt,confirmationSummary:changedConfirmation),"A changed confirming assessment withdraws the old receipt")
        changedRequest=request;changedRequest.observedBodyFingerprint="observed-request-correction"
        reject(validJSON,requests:[requestAlias:changedRequest])
        check(!matches(receipt,requestSummary:changedRequest),"Observed request drift is unusable before reassessment")
        changedConfirmation=confirmation;changedConfirmation.observedBodyFingerprint="observed-confirmation-correction"
        reject(validJSON,confirmations:[confirmationAlias:changedConfirmation])
        check(!matches(receipt,confirmationSummary:changedConfirmation),"Observed confirmation drift is unusable before reassessment")
        changedRequest=request;changedRequest.bodyFingerprint="new-request-content"
        check(!matches(receipt,requestSummary:changedRequest),"Changed request body content withdraws the receipt")
        changedConfirmation=confirmation;changedConfirmation.bodyFingerprint="new-confirmation-content"
        check(!matches(receipt,confirmationSummary:changedConfirmation),"Changed confirmation body content withdraws the receipt")
        let edited=try message(2,received:confirmationDate,subject:"Orion assessment failed")
        check(!matches(receipt,confirmationMessage:edited),"A changed current confirmation header cannot use an old assessment")
        let replied=try message(1,received:requestDate,replied:true)
        check(!matches(receipt,requestMessage:replied),"Reply state is part of the captured assessment revision")
        changedConfirmation=confirmation;changedConfirmation.dismissed=true;changedConfirmation.dismissedAt=now
        check(matches(receipt,confirmationSummary:changedConfirmation),"Human Dismiss acknowledges the confirmation without deleting its evidence")
        check(try decode(validJSON,confirmations:[confirmationAlias:changedConfirmation]).count == 1,"Dismissed confirmation evidence remains eligible for comparison")
        changedRequest=request;changedRequest.replyDraft="An unsent human draft";changedRequest.replyDraftEdited=true
        check(matches(receipt,requestSummary:changedRequest),"Stored draft edits are preserved and do not invent new source evidence")
        changedRequest=request;changedRequest.resolution=receipt
        check(matches(receipt,requestSummary:changedRequest),"Saving the receipt must not invalidate its own base assessment")
        print("Email resolution checks passed (\(checks)).")
    }
}
