import SwiftUI

/// Human review of exact remembered identities. Source reports retain their separate evidence.
struct CommitmentReportsView:View {
    @Bindable var memory:PAMemoryStore
    var recordID:UUID
    var registration:String
    @Environment(\.dismiss) private var dismiss
    @State private var connecting=false
    @State private var candidate:PAMemory?
    @State private var capturedRevision:UUID?
    @State private var error:String?
    private var current:PAMemory? { memory.permittedRecords.first{$0.id == recordID && $0.registration == registration && $0.kind == .commitment && MemoryRules.usable($0,registration:registration)} }
    private var reports:[PAMemory] { current.map{CommitmentRules.reports($0,from:memory.permittedRecords)} ?? [] }
    private var candidates:[PAMemory] { current.map{value in memory.permittedRecords.filter{CommitmentRules.linkable(value,$0) && (value.commitmentGroup == nil || $0.commitmentGroup != value.commitmentGroup)}.sorted{$0.created > $1.created}} ?? [] }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Remembered plan reports").font(.title3.weight(.semibold));Spacer();Button("Done") { dismiss() } }
            Text("These are remembered accounts of a plan. Each keeps its own evidence. A reported change, cancellation or completion does not update Calendar or Reminders.").font(.caption).foregroundStyle(.secondary)
            if let current,memory.enabled {
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        ForEach(reports) { report in
                            VStack(alignment:.leading,spacing:6) {
                                Text(report.sourceState.map{"Source reports: " + $0.rawValue} ?? "No source-reported state").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(PAProse.display(report.text)).textSelection(.enabled)
                                Text(report.attribution).font(.caption).foregroundStyle(.secondary)
                                PAMemoryEvidenceView(record:report,sourcePermitted:true)
                                if report.commitmentGroup != nil { Text("Same plan · connected by you").font(.caption2).foregroundStyle(.secondary) }
                            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                        }
                        Text("Only currently usable reports appear here. Other reports may be outside current access or need review. Conflicting reports stay separate claims; connecting them does not choose which is true.").font(.caption).foregroundStyle(.secondary)
                        if connecting {
                            Divider();Text("Connect another report").font(.headline)
                            Text("Choose a report only if you know it concerns this same plan. Similar wording alone is not enough.").font(.caption).foregroundStyle(.secondary)
                            ForEach(candidates) { item in
                                Button { candidate=item;capturedRevision=memory.revision } label: {
                                    VStack(alignment:.leading,spacing:4) { Text(PAProse.display(item.text)).font(.callout);Text(item.attribution).font(.caption).foregroundStyle(.secondary) }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(candidate?.id == item.id ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03),in:RoundedRectangle(cornerRadius:9))
                                }.buttonStyle(.plain)
                            }
                            if candidates.isEmpty { Text("No other available commitment reports in this scope.").font(.caption).foregroundStyle(.secondary) }
                            if let candidate {
                                Text("Connect the selected report to this same plan?").font(.callout.weight(.semibold))
                                Button("Yes, same plan") {
                                    guard memory.records.first(where:{$0.id == candidate.id}) == candidate,let capturedRevision else { error="The selected report changed. Choose it again.";return }
                                    if memory.connectCommitments(current.id,candidate.id,registration:registration,expectedRevision:capturedRevision) { connecting=false;self.candidate=nil;error=nil }
                                    else { error=memory.error }
                                }.buttonStyle(.borderedProminent)
                            }
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button(connecting ? "Cancel connection" : "Connect another report…") { connecting.toggle();candidate=nil;capturedRevision=nil;error=nil }
                    Spacer()
                    if current.commitmentGroup != nil { Button("Keep this report separate") { if memory.disconnectCommitment(current.id,registration:registration,expectedRevision:memory.revision) { candidate=nil;connecting=false;error=nil } else { error=memory.error } } }
                }.controlSize(.small)
            } else { ContentUnavailableView("Report unavailable",systemImage:"clock.badge.questionmark",description:Text("It may have changed, been resolved or lost source access. Reopen its current memory before connecting reports.")) }
        }.padding(24).frame(width:560,height:620)
    }
}
