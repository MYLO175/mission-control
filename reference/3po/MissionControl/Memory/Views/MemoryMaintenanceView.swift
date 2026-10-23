import SwiftUI

struct MemoryMaintenanceView:View {
    var model:DashboardModel
    var inspect:([UUID])->Void
    @State private var retired:PAMemory?
    var body:some View {
        let service=model.memoryMaintenance,memory=model.assistant.memory,registration=model.chatGPT.activeID
        VStack(alignment:.leading,spacing:10) {
            Text("Memory review").font(.headline)
            Text("The AI can flag repeated facts, possible conflicts and old provisional assumptions. Suggestions never rewrite facts, merge identities, delete evidence or edit your projects. This reviews human memories only, in a bounded sample.").font(.caption).foregroundStyle(.secondary)
            Toggle("Offer a weekly background review",isOn:Binding(get:{service.automatic(registration)},set:{service.setAutomatic($0,registration:registration)}))
            Text("Off by default. An enabled review shares the existing learning allowance; it is not an extra daily job. Review now explicitly assesses one sample.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(service.paused(registration) ? "Resume review now" : "Review now") { service.check(model,manual:true) }
                    .disabled(service.busy || model.chatGPT.busy || model.assistant.busy || !memory.enabled || !memory.learningEnabled || !model.chatGPT.inferenceVerified || model.chatGPT.usagePaused)
                if service.busy { Button("Stop review") { service.cancel() } }
            }
            Text(service.status).font(.caption).foregroundStyle(.secondary)
            if let error=service.error { Text(error).font(.caption).foregroundStyle(.orange) }
            ForEach(service.proposals(memory,registration:registration)) { proposal in
                VStack(alignment:.leading,spacing:8) {
                    Text(proposal.kind.title).font(.callout.weight(.semibold))
                    Text(proposal.reason).font(.callout)
                    ForEach(proposal.recordIDs,id:\.self) { id in
                        if let record=memory.records.first(where:{$0.id == id}) {
                            Text(record.text).textSelection(.enabled)
                            PAMemoryEvidenceView(record:record,sourcePermitted:true)
                        }
                    }
                    HStack {
                        Button("Review these facts") { inspect(proposal.recordIDs) }
                        if proposal.kind == .retirement,let id=proposal.recordIDs.first {
                            Button("Retire from recall") {
                                guard MemoryReviewRules.current(proposal,records:memory.records,registration:registration) else { return }
                                if memory.retire(id,retired:true,expectedRevision:memory.revision) { retired=memory.records.first(where:{$0.id == id}) }
                            }
                        }
                        Button("Dismiss") { service.dismiss(proposal.id,registration:registration) }
                    }.controlSize(.small)
                    Text("Duplicate/conflict suggestions ask you to inspect and correct the facts. Similar names alone cannot combine people or projects.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
            }
            if service.undoDate(registration) != nil { Button("Undo dismissed review") { service.undo(registration) } }
            if let retired,memory.records.first(where:{$0.id == retired.id}) == retired {
                Button("Restore last retired fact") { if memory.retire(retired.id,retired:false,expectedRevision:memory.revision) { self.retired=nil } }
            }
        }
    }
}
