import SwiftUI
struct DiscoveryEvidenceView:View {
    var record:PADiscovery
    var model:DashboardModel?
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Source evidence").font(.title3.weight(.semibold))
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    if model.map({$0.proactive.sourceEvidenceAvailable(record,model:$0)}) ?? true {
                        if let model,let details=model.proactive.sourceDetails(record,model:model) {ReviewSourceDetailsView(details:details)}
                        Text(record.evidence).textSelection(.enabled)
                    }
                    else { Text("The original source is no longer available in your selected context.").foregroundStyle(.secondary) }
                    if let model {
                        MemoryAdviceEvidenceView(model:model,registration:record.registration,dependencies:record.memoryDependencies,use:record.memoryUse ?? .suggestions)
                        let earlier=model.proactive.earlierVersions(record)
                        if !earlier.isEmpty {
                            DisclosureGroup("Earlier suggestions (\(earlier.count))") {
                                if model.proactive.reviewEvidenceAvailable(record.id,model:model),let reason=record.replacementReason {Text(reason).font(.callout).padding(.vertical,6)}
                                ForEach(earlier) { old in
                                    VStack(alignment:.leading,spacing:5) {
                                        Text("Replaced · " + (old.supersededAt ?? old.created).formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                                        if model.proactive.sourceEvidenceAvailable(old,model:model) {
                                            if let details=model.proactive.sourceDetails(old,model:model) {ReviewSourceDetailsView(details:details)}
                                            Text(old.evidence).textSelection(.enabled)
                                            if let change=old.proposedChange {Text("Suggested date: " + change.newDate).font(.caption).foregroundStyle(.secondary)}
                                        } else {Text("Original evidence unavailable.").font(.caption).foregroundStyle(.secondary)}
                                    }.padding(.vertical,6)
                                }
                            }
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.frame(maxHeight:480)
            Text(record.sourceKind == "whatsapp" ? "This suggestion is based on the quoted message. Linked-device history can be incomplete." : "This suggestion is based on the email’s quoted evidence; other source coverage may be incomplete.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer();Button("Done") { dismiss() } }
        }.padding(24).frame(width:460)
    }
}
struct ReviewSourceLabel:View {
    var details:ReviewSourceDetails
    var showsTitle=false
    var body:some View {
        VStack(alignment:.leading,spacing:3) {
            if showsTitle,let title=details.title {Text(title).font(.caption.weight(.medium)).textSelection(.enabled)}
            Text(details.channel + " · " + details.location + " · " + details.sender + " · " + details.dateLabel + " " + details.date.formatted(date:.abbreviated,time:.shortened))
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
        }
    }
}
struct ReviewSourceDetailsView:View {
    var details:ReviewSourceDetails
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            Label(details.channel + " · " + details.location,systemImage:details.kind == "whatsapp" ? "bubble.left" : "envelope").font(.subheadline.weight(.semibold))
            if let title=details.title {Text(title).font(.callout.weight(.semibold))}
            Text("From: " + details.sender).font(.callout)
            Text(details.dateLabel + ": " + details.date.formatted(date:.complete,time:.shortened)).font(.caption).foregroundStyle(.secondary)
        }.textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
    }
}
