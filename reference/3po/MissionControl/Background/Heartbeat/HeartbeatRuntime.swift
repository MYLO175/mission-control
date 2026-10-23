import Foundation

/// Current ownership and availability, read again at every orchestration boundary.
/// Child workers remain responsible for validating their exact supplied evidence.
struct HeartbeatEnvironment {
    var registration:String
    var model:String
    var sourceSettings:String
    var scope:String
    var whatsappChoices:UUID
    var whatsappIdentity:String
    var contextEnabled:Bool
    var inferenceVerified:Bool
    var usagePaused:Bool
    var workBusy:Bool
    var foregroundBusy:Bool
    var permitted:Bool
    var emailEnabled:Bool
    var proposalsEnabled:Bool
    var proposalAllowanceReached:Bool
}

struct HeartbeatSources {
    var mailReview:MailReviewScope
    var accounts:[MailAccount]
    var enabledMail:Set<String>
    var nativeReady:Bool
    var wantsWhatsApp:Bool
    var whatsappReady:Bool
}

@MainActor struct HeartbeatSourceRequest {
    var registration:String
    var whatsappEnabled:Bool
    var clock:()->Date
    var validate:() throws->Void
}

struct HeartbeatPending {
    var any:Bool
    var mailAccounts:Set<String>
    var proposals:Bool
}

struct HeartbeatActivity {
    var preparedItems=0
    var emailDrafts=0
    var whatsappDrafts=0
    var handled=0
    var briefUpdated=false
    var questions=0
}

/// A successful claim is persisted by the parent before the child may infer.
/// The captured closure expires with this particular run, even for the same owner.
@MainActor struct HeartbeatChildRequest {
    var registration:String
    var manual:Bool
    var runID:String
    var mailReview:MailReviewScope
    var whatsappReady:Bool
    var claim:() throws->Void
    /// Recheck this exact parent run immediately before a child saves output.
    /// Cancellation can reach the parent before the child task is unwound.
    var validate:() throws->Void
}

struct HeartbeatChildResult {
    var failure:String? = nil
    var nativeUnavailable=false
    var detail:String? = nil
    var skipped=false
}

/// The scheduler owns due dates, receipts, allowance and interruption recovery.
/// These ports only supply current collected context and run the bounded child stages.
/// They expose no Mail collection, native mutation or foreground queue operation.
@MainActor struct HeartbeatRuntime {
    var environment:()->HeartbeatEnvironment
    var prepareSources:(HeartbeatSourceRequest) async throws->HeartbeatSources
    var currentSources:(_ whatsappReady:Bool)->HeartbeatSources
    var availableMail:(MailReviewScope)->MailReviewScope
    var sourceFingerprint:(_ mailReview:MailReviewScope,_ whatsappReady:Bool,_ whatsappEnabled:Bool)->String
    var mailFingerprints:(MailReviewScope)->[String:String]
    var pending:(_ mailReview:MailReviewScope,_ whatsappReady:Bool,_ nativeReady:Bool)->HeartbeatPending
    var activity:(_ registration:String,_ runID:String)->HeartbeatActivity
    var email:(HeartbeatChildRequest) async throws->HeartbeatChildResult
    var suggestions:(HeartbeatChildRequest) async throws->HeartbeatChildResult
    var brief:(HeartbeatChildRequest) async throws->HeartbeatChildResult
    var cancelChildren:()->Void
    var feedback:(HeartbeatChildRequest) async throws->HeartbeatChildResult = {_ in .init(skipped:true)}
    var learning:(HeartbeatChildRequest) async throws->HeartbeatChildResult = {_ in .init(skipped:true)}

    var started:(_ registration:String,_ runID:String,_ date:Date)->Void = {_,_,_ in}
    var finished:(_ registration:String,_ run:PAReviewRun)->Void = {_,_ in}

    #if DEBUG
    /// Metadata-only legacy evaluation uses no desktop or real child workers.
    static var inactive:Self {
        let choices=UUID()
        let mail=MailReviewScope.collected(index:MailIndexState(),snapshot:MailSnapshot(messages:[],accounts:[],errors:[]),excluded:[])
        let sources=HeartbeatSources(mailReview:mail,accounts:[],enabledMail:[],nativeReady:false,wantsWhatsApp:false,whatsappReady:false)
        return .init(environment:{.init(registration:"",model:"",sourceSettings:"",scope:"",whatsappChoices:choices,whatsappIdentity:"",contextEnabled:false,inferenceVerified:false,usagePaused:false,workBusy:false,foregroundBusy:false,permitted:false,emailEnabled:false,proposalsEnabled:false,proposalAllowanceReached:false)},prepareSources:{_ in sources},currentSources:{_ in sources},availableMail:{$0},sourceFingerprint:{_,_,_ in ""},mailFingerprints:{_ in [:]},pending:{_,_,_ in .init(any:false,mailAccounts:[],proposals:false)},activity:{_,_ in .init()},email:{_ in .init()},suggestions:{_ in .init()},brief:{_ in .init()},cancelChildren:{})
    }
    #endif
}
