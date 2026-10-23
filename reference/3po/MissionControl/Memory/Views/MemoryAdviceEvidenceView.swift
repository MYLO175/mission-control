import SwiftUI

/// Local inspection of the captured supporting facts; never refreshes sources or invokes inference.
struct MemoryAdviceEvidenceView:View {
    var model:DashboardModel
    var registration:String
    var dependencies:[MemoryDependency]?
    var use:AutomaticMemoryUse
    @State private var expanded=false
    var body:some View {
        if registration == model.chatGPT.activeID {
            if let dependencies {
                DisclosureGroup("Memory supplied (\(dependencies.count) facts)",isExpanded:$expanded) {
                    if expanded {
                let records=model.memoryDependencyRecords(dependencies,use:use).filter { record in
                    dependencies.contains{$0.id == record.id.uuidString && $0.fingerprint == MemoryDependencyRules.fingerprint(MemoryRetrieval.record(record))}
                }
                    VStack(alignment:.leading,spacing:10) {
                        Text(use == .brief ? "Context supplied for this brief; this does not show which facts influenced the wording." : "Context supplied to the review batch, which may cover several messages. This does not show which facts influenced this suggestion.").font(.caption).foregroundStyle(.secondary)
                        if records.count < dependencies.count { Text("\(dependencies.count-records.count) supporting facts have changed or are unavailable under current access. This advice is a dated record.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(records) { record in
                            VStack(alignment:.leading,spacing:5) {
                                Text(record.text).textSelection(.enabled)
                                Text(record.attribution).font(.caption).foregroundStyle(.secondary)
                                PAMemoryEvidenceView(record:record,sourcePermitted:true)
                            }
                        }
                        if dependencies.isEmpty { Text("No saved facts were supplied.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.top,8)
                    }
                }.font(.callout)
            } else { Text("This older record predates saved memory receipts.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
