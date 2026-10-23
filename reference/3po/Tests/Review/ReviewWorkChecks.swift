import Foundation

@MainActor private final class ReviewWorkFixture {
    var bytes:Data?
    var commits=0
    var failNext=false
    var failAfter:Int?
    var scope=ReviewWorkScope(registration:"owner-a",model:"model-a",sourceChoices:"sources-a",storage:"storage-a")
    var ready=true
    var permitted=true
    var calls:[String]=[]
    var observed:[ReviewWorkJob]=[]
    var canonical:[String:ReviewWorkActionResult]=[:]
    var hold=false
    var held:CheckedContinuation<Void,Never>?
    var conversationHeld:CheckedContinuation<Void,Never>?
    var converseCalls=0
    var conversationModels:[String]=[]
    var cancels=0
    var performResult=ReviewWorkActionResult(phase:.saved,message:"Verified fictional save",itemID:"item",location:"Example")
    var conversationResult=ReviewWorkConversationResult(phase:.completed,message:"Reply ready",confirmedActions:0)
    var canonicalOnReturn=false
    var throwPerform=false
    var driveOnChange=false
    var stopOnRunning=false
    weak var service:ReviewWorkService?
    enum FixtureError:Error {case failed}
    func persist(_ value:Data)throws {
        commits += 1
        if failNext {failNext=false;throw FixtureError.failed}
        if let failAfter,commits >= failAfter {throw FixtureError.failed}
        bytes=value
    }
    func make()->ReviewWorkService {
        let value=ReviewWorkService(load:{self.bytes},persist:{try self.persist($0)})
        service=value
        return value
    }
    func runtime()->ReviewWorkRuntime {
        .init(scope:{self.scope},ready:{self.ready},permits:{_ in self.permitted},perform:{job,action,valid in
            self.calls.append(action.id)
            if self.hold {self.hold=false;await withCheckedContinuation {self.held=$0}}
            if self.throwPerform {throw FixtureError.failed}
            if self.canonicalOnReturn {self.canonical[action.id]=self.performResult}
            return self.performResult
        },inspect:{_,action in self.canonical[action.id]},converse:{job,valid in
            self.converseCalls += 1;self.conversationModels.append(job.scope.model)
            if self.hold {self.hold=false;await withCheckedContinuation {self.conversationHeld=$0}}
            return self.conversationResult
        },cancelConversation:{self.cancels += 1},changed:{value in
            self.observed.append(value)
            if self.stopOnRunning && value.phase == .running {self.stopOnRunning=false;self.service?.stop(value.id)}
            if self.driveOnChange {self.service?.drive(self.runtime())}
        })
    }
    func release() {let continuation=held;held=nil;continuation?.resume();let converse=conversationHeld;conversationHeld=nil;converse?.resume()}
    func action(_ id:String)->ReviewWorkAction {.init(id:id,title:"Task "+id,destination:"Project",payload:Data(id.utf8))}
    func job(_ id:String="a",mode:ReviewWorkMode = .approval)->ReviewWorkJob {
        .init(conversationID:UUID(),scope:scope,source:.init(key:"email:source",title:"Example schedule",kind:"mail",accountID:"mail-a",messageID:"message-a"),mode:mode,human:"Yes",actions:mode == .approval ? [action(id)] : [])
    }
}

@main struct ReviewWorkChecks {
    @MainActor static func main()async throws {
        var total=0
        func check(_ value:Bool,_ text:String) {precondition(value,text);total += 1}
        func until(_ condition:()->Bool)async {for _ in 0..<20_000 {if condition(){return};await Task.yield()};preconditionFailure("Fictional Review work did not settle")}
        do {
            let w=ReviewWorkFixture(),s=w.make();w.ready=false
            let one=w.job("one"),two=w.job("two")
            check(s.submit(one) && s.submit(two),"Durable submissions accepted while heartbeat blocks runtime")
            s.drive(w.runtime());check(!s.busy && w.calls.isEmpty && s.waiting(w.scope.registration)==2,"Heartbeat ready gate prevents starts")
            let bytes=w.bytes!
            let reopened=ReviewWorkService(load:{bytes},persist:{try w.persist($0)})
            check(reopened.job(one.id)?.phase == .queued,"Never-started work survives reopen without becoming interrupted")
            w.ready=true;w.hold=true;s.drive(w.runtime());await until{w.held != nil}
            s.drive(w.runtime());check(w.calls == ["one"],"One active operation serialises independent drive calls")
            w.release();await until{!s.busy};check(s.job(one.id)?.phase == .completed && s.job(two.id)?.phase == .queued,"First completion retains later queued work")
            s.drive(w.runtime());await until{!s.busy};check(s.job(two.id)?.phase == .completed && w.calls == ["one","two"],"Later explicit drive executes second request exactly once")
            check(s.jobs(w.scope.registration).map(\.id) == [one.id,two.id],"Queue retains identities and insertion order")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();w.driveOnChange=true
            _=s.submit(w.job("one"));_=s.submit(w.job("two"));s.drive(w.runtime());await until{!s.busy}
            check(s.waiting(w.scope.registration)==0,"Completion callback can drive next queued job without polling or another human action")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job();w.hold=true;_=s.submit(job);s.drive(w.runtime());await until{w.held != nil}
            let runningBytes=w.bytes!
            let reopened=ReviewWorkService(load:{runningBytes},persist:{_ in})
            check(reopened.job(job.id)?.phase == .interrupted,"Reopen interrupts attempted work without requeuing it")
            check(reopened.job(job.id)?.actions[0].phase == .uncertain,"Working action recovers conservatively as uncertain")
            reopened.drive(w.runtime());check(w.calls.count==1,"Reopened attempted work never replays")
            check(!reopened.retry(job.id),"Explicit retry cannot repeat an uncertain operation")
            w.canonical["a"] = .init(phase:.saved,message:"Readback verified",itemID:"original")
            _=reopened.reconcile(job.id,runtime:w.runtime())
            check(reopened.job(job.id)?.actions[0].phase == .saved,"Canonical readback can reconcile an interrupted uncertain action without another creation")
            s.stop(job.id);w.release();await until{!s.busy}
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job();w.canonical["a"] = .init(phase:.saved,message:"Already verified",itemID:"original")
            _=s.submit(job);s.drive(w.runtime());await until{!s.busy}
            check(w.calls.isEmpty && s.job(job.id)?.phase == .completed && s.job(job.id)?.actions[0].itemID == "original","Canonical complete receipt avoids duplicate action")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job();w.canonical["a"] = .init(phase:.uncertain,message:"Pending native receipt")
            _=s.submit(job);s.drive(w.runtime());await until{!s.busy}
            check(w.calls.isEmpty && s.job(job.id)?.phase == .uncertain,"Canonical pending receipt blocks that operation and exposes uncertain result")
        }
        for mode in [ReviewWorkMode.approval,.conversation] {
            for change in ["registration","model","sourceChoices","storage","permission"] {
                let w=ReviewWorkFixture(),s=w.make(),job=w.job(mode:mode);w.hold=true
                _=s.submit(job);s.drive(w.runtime());await until{w.held != nil || w.conversationHeld != nil}
                switch change {
                case "registration":w.scope.registration="owner-b"
                case "model":w.scope.model="model-b"
                case "sourceChoices":w.scope.sourceChoices="sources-b"
                case "storage":w.scope.storage="storage-b"
                default:w.permitted=false
                }
                w.release();await until{!s.busy}
                check(["model","sourceChoices"].contains(change) ? s.job(job.id)?.phase == .completed : s.job(job.id)?.phase != .completed,"Late \(mode.rawValue) result retains captured defaults and rejects unavailable ownership after \(change)")
                check(s.job(job.id)?.scope == job.scope,"Captured \(mode.rawValue) model/source defaults remain stored after \(change)")
                if mode == .conversation {check(w.conversationModels == [job.scope.model],"Conversation executes only its captured model after \(change)")}
            }
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job(mode:.conversation);w.hold=true
            _=s.submit(job);s.drive(w.runtime());await until{w.conversationHeld != nil};s.stop(job.id);w.release();await until{!s.busy}
            check(s.job(job.id)?.phase == .stopped && s.job(job.id)?.message == nil && w.cancels==1,"Stop rejects late conversation text and calls cancellation once")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job();w.hold=true;w.canonicalOnReturn=true
            _=s.submit(job);s.drive(w.runtime());await until{w.held != nil};s.stop(job.id);w.release();await until{!s.busy}
            check(s.job(job.id)?.phase == .stopped && s.job(job.id)?.savedCount == 1,"Stop keeps confirmed already-issued save while stopping overall request")
            s.drive(w.runtime());check(w.calls.count==1,"Stop never requeues its attempted operation")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();var job=w.job();job.actions.append(w.action("b"));w.performResult = .init(phase:.failed,message:"Known pre-save failure")
            _=s.submit(job);s.drive(w.runtime());await until{!s.busy}
            check(s.job(job.id)?.phase == .failed && s.job(job.id)?.actions[1].phase == .waiting && w.calls == ["a"],"Failure isolates remaining actions and pauses progression")
            let old=s.job(job.id)!,turn=old.humanTurnID,response=old.responseTurnID
            check(s.retry(job.id),"Explicit known-safe Retry permits unattempted remainder")
            check(s.job(job.id)?.id == job.id && s.job(job.id)?.humanTurnID == turn && s.job(job.id)?.responseTurnID != response && s.job(job.id)?.actions.map(\.payload) == job.actions.map(\.payload),"Retry preserves human operation/action identity and captured payload")
            w.performResult = .init(phase:.saved,message:"Verified");s.drive(w.runtime());await until{!s.busy}
            check(s.job(job.id)?.phase == .completed,"Explicit Retry can finish known failed operation")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();var first=w.job();first.actions.append(w.action("b"));let same=w.job()
            check(s.submit(first),"First selected plan is saved")
            var duplicate=same;duplicate.actions=first.actions
            check(!s.submit(duplicate) && s.state.jobs.count==1,"Same ordered concrete pending plan coalesces")
            var reordered=w.job();reordered.actions=Array(first.actions.reversed())
            check(!s.submit(reordered),"Same concrete plan coalesces regardless of checkbox/input order")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job();w.failNext=true
            check(!s.submit(job) && s.state.jobs.isEmpty && w.bytes == nil,"Failed initial persistence accepts no job and performs no action")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();let first=w.job("a"),second=w.job("b")
            _=s.submit(first);_=s.submit(second);w.hold=true;s.drive(w.runtime());await until{w.held != nil}
            // Permanently fail all writes once the first operation has been issued.
            w.failAfter=w.commits+1;w.release();await until{!s.busy}
            check(s.job(first.id)?.phase != .completed && s.error != nil,"Receipt/checkpoint persistence failure cannot claim completion")
            // Storage later recovers, but uncertain first work must pause further writes.
            w.failAfter=nil;s.drive(w.runtime());await until{!s.busy}
            check(w.calls == ["a"] && s.job(second.id)?.phase == .queued,"Progress storage failure latches queue pause after storage recovers")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();var fabricated=w.job();fabricated.actions[0].phase = .saved;fabricated.actions[0].result="Not inspected"
            check(!s.submit(fabricated),"New approval jobs cannot fabricate pre-saved action outcomes")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job(mode:.conversation);w.conversationResult = .init(phase:.queued,message:"Invalid runtime terminal phase")
            _=s.submit(job);s.drive(w.runtime());await until{!s.busy};s.drive(w.runtime());await until{!s.busy}
            check(w.converseCalls==1 && s.job(job.id)?.phase != .queued,"Unexpected nonterminal conversation result cannot become automatic replay")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();var job=w.job("a");job.actions.append(w.action("b"))
            w.hold=true;_=s.submit(job);s.drive(w.runtime());await until{w.held != nil}
            w.failNext=true;w.release();await until{!s.busy}
            check(w.calls == ["a"],"One failed confirmed-result checkpoint stops remaining native actions")
        }
        for mode in [ReviewWorkMode.approval,.conversation] {
        for change in ["model","sourceChoices","storage","permission"] {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job(mode:mode);_=s.submit(job)
            switch change {
            case "model":w.scope.model="model-b"
            case "sourceChoices":w.scope.sourceChoices="sources-b"
            case "storage":w.scope.storage="storage-b"
            default:w.permitted=false
            }
            s.drive(w.runtime())
            await until{!s.busy}
            check(["model","sourceChoices"].contains(change) ? s.job(job.id)?.phase == .completed : w.calls.isEmpty && w.converseCalls == 0 && s.job(job.id)?.phase == .failed,"Queued \(mode.rawValue) retains captured defaults and rejects unavailable ownership after \(change)")
            if mode == .conversation,["model","sourceChoices"].contains(change) {check(w.conversationModels == [job.scope.model] && s.job(job.id)?.scope == job.scope,"Queued conversation keeps its submitted model without retargeting")}
        }
        }
        for mode in [ReviewWorkMode.approval,.conversation] {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job(mode:mode);w.hold=true
            _=s.submit(job);s.drive(w.runtime());await until{w.held != nil || w.conversationHeld != nil}
            s.setDraft("Independent unsent reply",registration:job.scope.registration,conversation:job.conversationID)
            w.ready=false
            w.scope.model="next-model";w.scope.sourceChoices="new-unrelated-source-defaults"
            check(s.job(job.id)?.phase == .running && w.cancels == 0,"Editing a saved draft and changing start readiness do not Stop \(mode.rawValue)")
            w.release();await until{!s.busy}
            check(s.job(job.id)?.phase == .completed && s.draft(job.scope.registration,conversation:job.conversationID) == "Independent unsent reply","Held \(mode.rawValue) finishes with the independent draft intact")
            let reopened=ReviewWorkService(load:{w.bytes},persist:{try w.persist($0)})
            check(reopened.job(job.id)?.phase == .completed && reopened.draft(job.scope.registration,conversation:job.conversationID) == "Independent unsent reply","Completed \(mode.rawValue) and unsent draft survive reopening")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job(mode:.conversation);_=s.submit(job);w.conversationResult = .init(phase:.needsAnswer,message:"Which deadline?")
            s.drive(w.runtime());await until{!s.busy}
            check(s.job(job.id)?.phase == .needsAnswer,"Needs-answer retains the question without requeuing it")
        }
        // The production idle pump repeatedly calls drive; terminal jobs must not block unrelated accepted work.
        for phase in [ReviewWorkPhase.failed,.partial,.uncertain,.needsAnswer,.stopped,.interrupted] {
            let w=ReviewWorkFixture(),s=w.make();w.driveOnChange=true
            let first=w.job(mode:.conversation),second=w.job("next")
            w.conversationResult = .init(phase:phase,message:"Retained outcome",confirmedActions:phase == .partial ? 1 : 0)
            _=s.submit(first);_=s.submit(second);s.drive(w.runtime());await until{s.job(second.id)?.phase == .completed && !s.busy}
            check(s.job(first.id)?.phase == phase && w.converseCalls==1 && w.calls == ["next"],"\(phase.rawValue) stays terminal while later accepted work runs automatically exactly once")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();let first=w.job(),second=w.job("next")
            _=s.submit(first);_=s.submit(second);w.hold=true;s.drive(w.runtime());await until{w.held != nil}
            w.ready=false;s.interruptForForeground(w.scope.registration);s.drive(w.runtime())
            check(s.job(first.id)?.phase == .stopped && s.job(second.id)?.phase == .queued && w.calls == ["a"],"Foreground handover retains later work and waits for the active callback to unwind")
            w.release();await until{!s.busy};s.drive(w.runtime())
            check(s.job(second.id)?.phase == .queued,"Foreground typing or chat readiness temporarily defers accepted work")
            w.ready=true;s.drive(w.runtime());await until{!s.busy}
            check(w.calls == ["a","next"] && s.job(second.id)?.phase == .completed,"Accepted work starts once foreground readiness returns without Continue")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();let stopped=w.job("stopped"),next=w.job("next")
            _=s.submit(stopped);_=s.submit(next);s.stop(stopped.id);s.drive(w.runtime());await until{!s.busy}
            check(s.job(stopped.id)?.phase == .stopped && w.calls == ["next"],"Targeted Stop cancels only the selected unstarted job")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();let attempted=w.job(),next=w.job("next")
            _=s.submit(attempted);_=s.submit(next);w.hold=true;s.drive(w.runtime());await until{w.held != nil}
            var saved=try JSONDecoder().decode(ReviewWorkState.self,from:w.bytes!);saved.paused[w.scope.registration]=true
            let legacy=try JSONEncoder().encode(saved)
            let reopened=ReviewWorkService(load:{legacy},persist:{try w.persist($0)})
            w.release();await until{!s.busy};w.calls=[];reopened.drive(w.runtime());await until{!reopened.busy}
            check(reopened.job(attempted.id)?.phase == .interrupted && reopened.job(attempted.id)?.actions[0].phase == .uncertain && w.calls == ["next"],"Legacy paused queues resume only unstarted work after reopen; uncertain attempted saves never replay")
            check(reopened.state.paused[w.scope.registration] == true && reopened.job(next.id)?.phase == .completed,"Legacy pause metadata and original job identities survive without blocking idle execution")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();let failed=w.job(),next=w.job("next")
            w.canonical["a"] = .init(phase:.uncertain,message:"Unconfirmed original save")
            _=s.submit(failed);_=s.submit(next);w.driveOnChange=true;s.drive(w.runtime());await until{!s.busy && s.waiting(w.scope.registration)==0}
            check(w.calls == ["next"] && s.job(failed.id)?.phase == .uncertain && !s.retry(failed.id),"Uncertain canonical save does not replay or withhold the next independent approved action")
        }
        do {
            let bytes=Data("corrupt".utf8);var persisted=false
            let s=ReviewWorkService(load:{bytes},persist:{_ in persisted=true})
            check(!s.readable && !persisted && !s.submit(ReviewWorkFixture().job()),"Corrupt saved state stays untouched and disables submissions")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job(mode:.conversation);w.stopOnRunning=true
            _=s.submit(job);s.drive(w.runtime());await until{!s.busy}
            check(w.converseCalls==0 && s.job(job.id)?.phase == .stopped,"Stop from running notification prevents the first conversation call")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job(mode:.conversation);w.hold=true
            _=s.submit(job);s.drive(w.runtime());await until{w.conversationHeld != nil};s.stop(job.id)
            check(!s.retry(job.id),"Retry waits for a stopped conversation callback to unwind before replacing its response identity")
            w.release();await until{!s.busy}
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();_=s.submit(w.job())
            var object=try JSONSerialization.jsonObject(with:w.bytes!) as! [String:Any];object["futureField"]="retained"
            let original=try JSONSerialization.data(withJSONObject:object);var wrote=false
            let future=ReviewWorkService(load:{original},persist:{_ in wrote=true})
            check(!future.readable && !wrote,"Future fields preserve original bytes and disable queue writes")
        }
        do {
            check(ReviewSelectionRules.approvalTitle(0) == "No actions","Zero selection clearly closes without approval")
            check(ReviewSelectionRules.approvalTitle(1) == "Approve 1 action","Singular approval names exactly one action")
            check(ReviewSelectionRules.approvalTitle(2) == "Approve 2 actions","Plural approval names its exact count")
            let w=ReviewWorkFixture(),job=w.job()
            var plan=ReviewWorkPlan(conversationID:job.conversationID,scope:job.scope,source:job.source,actions:[w.action("a")],selected:["a"])
            check(ReviewSelectionRules.initial(plan).isEmpty,"Legacy automatic checkbox selections reset locally")
            plan.presentationVersion=2
            check(ReviewSelectionRules.initial(plan).isEmpty,"Earlier preselected plans default to zero")
            plan.presentationVersion=ReviewSelectionRules.version
            check(ReviewSelectionRules.initial(plan) == ["a"],"Later deliberate checkbox choices survive reopening")
            plan.selected=[]
            check(ReviewSelectionRules.initial(plan).isEmpty,"New plans begin with no checked actions")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make(),job=w.job()
            var plan=ReviewWorkPlan(conversationID:job.conversationID,scope:job.scope,source:job.source,actions:[w.action("a"),w.action("b")],selected:["a","b"])
            plan.presentationVersion=2;plan.seenProposalIDs=["a","b","omitted"];plan.unpreparedProposalIDs=["unavailable"]
            check(s.savePlan(plan,expected:nil),"Prepared plan persists without submitting or executing its suggestions")
            s.selectPlan(["b"],registration:job.scope.registration,conversation:job.conversationID)
            let current=s.plan(job.scope.registration,conversation:job.conversationID)!
            check(current.selected == ["b"] && current.revision != plan.revision && s.state.jobs.isEmpty && w.calls.isEmpty,"Checkbox choices persist with a revision without write authority")
            check(!s.savePlan(plan,expected:plan.revision),"A stale AI draft cannot overwrite a newer checkbox choice")
            let reopened=ReviewWorkService(load:{w.bytes},persist:{try w.persist($0)})
            check(reopened.plan(job.scope.registration,conversation:job.conversationID) == current,"Reopen preserves exact plan identities, concrete payloads and checkbox choices")
            s.setDraft("Unsent question",registration:job.scope.registration,conversation:job.conversationID)
            check(s.submit(job) && s.draft(job.scope.registration,conversation:job.conversationID) == "Unsent question","Done's concrete approval retains an unsent conversation draft")
            plan=current;plan.actions[0].title="Retargeted action";plan.revision=UUID()
            check(!s.savePlan(plan,expected:current.revision) && s.plan(job.scope.registration,conversation:job.conversationID) == current,"A pending approval's exact captured action cannot be retargeted by a new plan")
            let next=w.job("b");var changed=next;changed.conversationID=job.conversationID;changed.human="Explain this";changed.mode = .conversation;changed.actions=[]
            check(s.submit(changed) && s.draft(job.scope.registration,conversation:job.conversationID).isEmpty,"Submitting an actual conversation reply clears only its own saved draft")
            var object=try JSONSerialization.jsonObject(with:w.bytes!) as! [String:Any]
            var plans=object["plans"] as! [[String:Any]]
            var actions=plans[0]["actions"] as! [[String:Any]];actions[0]["futureField"]="Preserved";plans[0]["actions"]=actions;object["plans"]=plans
            let futureBytes=try JSONSerialization.data(withJSONObject:object);var wrote=false
            let future=ReviewWorkService(load:{futureBytes},persist:{_ in wrote=true})
            check(!future.readable && !wrote,"Unknown nested draft fields are retained verbatim instead of being lost in a migration")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();w.canonicalOnReturn=true
            var job=w.job(mode:.conversation);job.actions=[w.action("a")]
            let plan=ReviewWorkPlan(conversationID:job.conversationID,scope:job.scope,source:job.source,actions:job.actions,selected:["a"])
            check(s.savePlan(plan,expected:nil) && s.submit(job),"Conversation keeps exact checkbox context without approving it")
            check(!s.reserved("a",registration:job.scope.registration),"Waiting conversational context does not reserve a suggestion")
            var runtime=w.runtime()
            runtime.converse={current,valid in
                do {
                    do {_=try await s.performCaptured(current.id,revision:UUID(),actions:["a"],valid:valid);check(false,"Stale execution must reject")} catch {check(w.calls.isEmpty,"Stale revision executes no action")}
                    do {_=try await s.performCaptured(current.id,revision:plan.revision,actions:["a","a"],valid:valid);check(false,"Duplicate IDs must reject")} catch {check(w.calls.isEmpty,"Repeated issued IDs execute no action")}
                    let result=try await s.performCaptured(current.id,revision:plan.revision,actions:["a"],valid:valid)
                    check(result.first?.phase == .saved && s.reserved("a",registration:current.scope.registration),"Immediate execution saves and reserves the same canonical checkbox identity")
                    _=try await s.performCaptured(current.id,revision:plan.revision,actions:["a"],valid:valid)
                    return .init(phase:.completed,message:"Saved",confirmedActions:1)
                } catch {preconditionFailure(error.localizedDescription)}
            }
            s.drive(runtime);await until{!s.busy}
            check(w.calls == ["a"] && s.job(job.id)?.savedCount == 1 && s.job(job.id)?.conversationActionCount == 0,"Repeated conversational execution counts one canonical operation without extra saves")
            let reopened=ReviewWorkService(load:{w.bytes},persist:{try w.persist($0)})
            check(reopened.job(job.id)?.actions.first?.phase == .saved && reopened.reserved("a",registration:job.scope.registration),"Reopen retains the completed checkbox and exact operation receipt")
            var done=w.job("a");done.conversationID=job.conversationID
            _=s.submit(done);s.drive(w.runtime());await until{!s.busy}
            check(w.calls == ["a"] && s.job(done.id)?.actions.first?.phase == .saved,"Done reconciles the conversational receipt instead of creating a duplicate")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();w.ready=false
            var conversation=w.job(mode:.conversation);conversation.actions=[w.action("a")]
            var approval=w.job("a");approval.conversationID=conversation.conversationID
            check(s.submit(conversation) && s.submit(approval),"Done can queue concrete approval while an explanation retains the same waiting checkbox context")
            check(!s.submit(w.job("a")),"A second exact concrete approval still coalesces with the pending approval")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();var job=w.job(mode:.conversation)
            job.actions=[w.action("a"),w.action("b")]
            let plan=ReviewWorkPlan(conversationID:job.conversationID,scope:job.scope,source:job.source,actions:job.actions,selected:["a","b"])
            check(s.savePlan(plan,expected:nil) && s.submit(job),"Legacy plans still decode without a presentation version")
            var actual=0,expected=0,refreshes=0
            var runtime=w.runtime()
            runtime.perform={_,action,_ in actual += 1;w.calls.append(action.id);w.canonical[action.id]=w.performResult;return w.performResult}
            runtime.converse={current,owned in
                let results=try! await s.performCaptured(current.id,revision:plan.revision,actions:["a","b"],valid:{owned() && actual == expected},didSave:{_ in expected=actual;refreshes += 1})
                return .init(phase:.completed,message:"Saved",confirmedActions:results.filter{$0.phase == .saved}.count)
            }
            s.drive(runtime);await until{!s.busy}
            check(w.calls == ["a","b"] && refreshes == 2 && s.job(job.id)?.savedCount == 2,"Each verified self-authored save refreshes its ownership before the next prepared action")
        }
        do {
            let w=ReviewWorkFixture(),s=w.make();var job=w.job(mode:.conversation)
            var earlier=w.action("earlier");earlier.phase = .saved;earlier.result="Earlier verified save";earlier.itemID="original-item"
            job.actions=[earlier]
            w.conversationResult = .init(phase:.needsAnswer,message:"Review the proposed actions",confirmedActions:3,error:"Waiting for approval")
            check(s.submit(job),"A conversation job with earlier verified actions can await direct chat approval")
            s.drive(w.runtime());await until{!s.busy}
            let waiting=s.job(job.id)!
            check(waiting.phase == .needsAnswer && waiting.conversationActionCount == 2 && waiting.savedCount == 3,"Waiting approval retains both canonical action receipts and earlier conversational successes")
            let next=w.job("next")
            check(s.submit(next),"Unrelated queued work is retained while the human approves a waiting conversation")
            let before=s.state,observed=w.observed.count,conversationCalls=w.converseCalls
            func finish(id:UUID?=nil,registration:String?=nil,conversation:UUID?=nil,response:UUID?=nil,phase:ReviewWorkPhase = .completed,count:Int=4)->Bool {
                s.finishChatApproval(jobID:id ?? job.id,registration:registration ?? job.scope.registration,conversationID:conversation ?? job.conversationID,responseID:response ?? job.responseTurnID,phase:phase,message:"Four more actions verified",error:nil,confirmedActions:count)
            }
            check(!finish(id:UUID()) && !finish(registration:"other-owner") && !finish(conversation:UUID()) && !finish(response:UUID()),"Chat approval completion requires the exact job, account, conversation and response identities")
            for phase:ReviewWorkPhase in [.queued,.running,.needsAnswer,.interrupted] {
                check(!finish(phase:phase),"Chat approval cannot move waiting work into nonterminal \(phase.rawValue) state")
            }
            check(!finish(count:-1) && s.state == before,"Rejected approval outcomes leave all jobs, receipts and counts unchanged")
            // A local completion must not invoke the callback that normally
            // starts queued work, even when that callback is configured to drive.
            w.driveOnChange=true
            check(finish(),"The exact waiting conversation accepts its verified chat approval outcome")
            let finished=s.job(job.id)!
            check(finished.phase == .completed && finished.finished != nil && finished.message == "Four more actions verified" && finished.error == nil,"Chat approval persists the terminal phase, finish time and current outcome")
            check(finished.conversationActionCount == 6 && finished.savedCount == 7 && finished.actions == waiting.actions && finished.scope == waiting.scope,"Direct approval adds four successes to the prior count and preserves exact earlier action receipts and scope")
            check(!finish() && s.job(job.id) == finished,"A second completion cannot count the same approval twice")
            check(s.activeID == nil && s.job(next.id)?.phase == .queued && w.calls.isEmpty && w.converseCalls == conversationCalls && w.observed.count == observed,"Finishing chat approval neither starts work nor advances or notifies the scheduler")
            let reopened=w.make()
            check(reopened.job(job.id) == finished && reopened.job(next.id)?.phase == .queued,"Terminal approval counts, original receipts and queued work survive reopening")
            check(!reopened.finishChatApproval(jobID:job.id,registration:job.scope.registration,conversationID:job.conversationID,responseID:job.responseTurnID,phase:.completed,message:"Duplicate",error:nil,confirmedActions:4) && reopened.job(job.id) == finished,"Reopening cannot replay the additive approval completion")
        }
        print("Review work: \(total)/\(total) source-free injected-runtime checks passed")
    }
}
