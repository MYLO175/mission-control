#if DEBUG
import SwiftUI

struct ReviewConversationTrialView: View {
    @State private var engine = ReviewTrialEngine()
    @State private var trial = true
    @State private var page = "Review"
    @State private var reviewOpen = false
    @State private var baselineOpen = false
    @State private var activityOpen = false
    @State private var dark = false
    @State private var sheetHeight:CGFloat = 740
    @Environment(\.colorScheme) private var scheme
    private var palette: WorkspacePalette { .resolved(raw:"{}",mode:dark ? "dark" : "light",theme:"warm",accent:"sage") }
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                Text("3PO").font(.system(size:23,weight:.semibold,design:.rounded)).padding(.horizontal,14).padding(.bottom,24)
                navigation("Today",icon:"square.grid.2x2")
                navigation("Review",icon:"tray.full")
                navigation("Projects",icon:"folder")
                navigation("Calendar",icon:"calendar")
                navigation("Chat",icon:"bubble.left.and.bubble.right")
                Spacer()
                VStack(alignment:.leading,spacing:6) {
                    Label("Interactive trial",systemImage:"testtube.2").font(.caption.weight(.medium))
                    Text("Example data\nSimulated jobs").font(.caption).foregroundStyle(palette[.text].opacity(0.62))
                }.padding(14)
            }.padding(.top,28).padding(.horizontal,12).frame(width:178).background(palette[.sidebar])
            VStack(alignment:.leading,spacing:22) {
                HStack {
                    Text(page == "Review" ? "Review inbox" : page == "Projects" ? "IIB MEng Project" : page == "Calendar" ? "Example Calendar" : page == "Chat" ? "3PO" : "Today").font(.system(size:27,weight:.semibold,design:.rounded))
                    if page == "Review" {Text("1").font(.caption.weight(.bold)).padding(.horizontal,8).padding(.vertical,4).background(palette[.accent].opacity(0.16),in:Capsule())}
                    Spacer()
                    if page == "Review" {Text("Prepared for you").font(.caption).foregroundStyle(palette[.text].opacity(0.62))}
                }
                if page == "Review" { reviewPage }
                else if page == "Projects" { results(engine.projectTasks,empty:"Project tasks will appear here after you approve the plan.") }
                else if page == "Calendar" { results(engine.calendarEntries,empty:"Calendar entries will appear here after you approve the plan.") }
                else if page == "Chat" { chatPage }
                else { todayPage }
                Spacer(minLength:0)
                HStack(spacing:6) {
                    Image(systemName:"info.circle")
                    Text("This trial uses a scripted example conversation. Nothing is written to your real project or Calendar.")
                }.font(.caption).foregroundStyle(palette[.text].opacity(0.62))
            }.padding(30).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(palette[.canvas],in:UnevenRoundedRectangle(topLeadingRadius:22)).padding(.top,8)
        }.background(palette[.sidebar]).foregroundStyle(palette[.text]).tint(palette[.accent]).environment(\.workspacePalette,palette)
            .frame(minWidth:820,minHeight:640)
            .onGeometryChange(for:CGFloat.self) {$0.size.height} action: {sheetHeight=max(480,min(740,$0-24))}
            .toolbar {
                ToolbarItem(placement:.navigation) {
                    Picker("Comparison",selection:$trial) {Text("Current idea").tag(false);Text("Trial").tag(true)}.pickerStyle(.segmented).frame(width:190)
                }
                ToolbarItem(placement:.principal) {
                    if trial {
                        ReviewTrialStatusPill(engine:engine,palette:palette,openChat:{page="Chat"},openActivity:{activityOpen.toggle()})
                            .popover(isPresented:$activityOpen,arrowEdge:.bottom) { ReviewTrialActivity(engine:engine,openReview:{activityOpen=false;reviewOpen=true},openResults:{activityOpen=false;page="Projects"}).padding(22).frame(width:420).environment(\.workspacePalette,palette).preferredColorScheme(dark ? .dark : .light) }
                    }
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItemGroup(placement:.primaryAction) {
                    if !trial {
                        if engine.heartbeatTicks != nil {ProgressView(value:engine.heartbeatProgress).frame(width:85);Text("\(Int(engine.heartbeatProgress*100))%").font(.caption)}
                        Button {page="Chat"} label:{Image(systemName:"bubble.left.and.bubble.right")}.help("Open chat")
                    }
                    Button {engine.startHeartbeat()} label:{Image(systemName:"waveform.path.ecg")}.disabled(engine.heartbeatTicks != nil || engine.activeJobID != nil || engine.queuedCount > 0).help("Run example heartbeat")
                    Menu {
                        Button("Run example heartbeat") {engine.startHeartbeat()}
                        Button("Finish heartbeat now") {engine.finishHeartbeat()}.disabled(engine.heartbeatTicks == nil)
                        Button("Advance one step") {engine.tick()}
                        Toggle("Advance automatically",isOn:$engine.automatic)
                        Divider()
                        Toggle("Next request: unconfirmed Calendar save",isOn:$engine.injectUncertainSave)
                        Button("Change example account") {engine.changeOwner()}
                        Button("Stop current job") {engine.stop()}.disabled(engine.heartbeatTicks == nil && engine.activeJobID == nil)
                        Toggle("Dark appearance",isOn:$dark)
                        Divider()
                        Button("Reset example") {engine.reset();page="Review"}
                    } label:{Image(systemName:"slider.horizontal.3")}.help("Demo controls")
                }
            }
            .toolbarBackground(palette[.sidebar],for:.windowToolbar).toolbarBackground(.visible,for:.windowToolbar)
            .preferredColorScheme(dark ? .dark : .light)
            .sheet(isPresented:$reviewOpen) { ReviewTrialConversation(engine:engine,palette:palette,height:sheetHeight).preferredColorScheme(dark ? .dark : .light) }
            .sheet(isPresented:$baselineOpen) { baselineSheet }
            .task {await engine.runClock()}
    }
    private func navigation(_ title:String,icon:String)->some View {
        Button {page=title} label:{HStack(spacing:11) {Image(systemName:icon).frame(width:20);Text(title).font(.callout.weight(page == title ? .semibold : .regular));Spacer();if title == "Review" {Circle().fill(palette[.accent]).frame(width:6,height:6)}}.padding(.horizontal,14).padding(.vertical,11).background(page == title ? palette[.accent].opacity(0.14) : .clear,in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain)
    }
    private var reviewPage:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                VStack(alignment:.leading,spacing:16) {
                    HStack {Label("Project dates",systemImage:"calendar.badge.clock").font(.caption.weight(.medium)).foregroundStyle(palette[.accent]);Spacer();Text("Example email").font(.caption).foregroundStyle(palette[.text].opacity(0.62))}
                    Text("Your IIB project milestones").font(.title2.weight(.semibold))
                    Text("The department’s project schedule includes your report deadlines and presentation dates. It also asks you to complete a hazard assessment with your supervisor.").lineSpacing(4)
                    Label("Connected to IIB MEng Project",systemImage:"folder").font(.caption).foregroundStyle(palette[.text].opacity(0.62))
                    Divider()
                    if trial {
                        Text("Let’s put the dates where you’ll use them.").font(.headline)
                        Text("I can add tasks inside your existing IIB project and place the deadlines and presentation dates in Calendar. The November dates are a window, so I’ll keep those provisional. The hazard assessment has no deadline in this example.").lineSpacing(4)
                        HStack(spacing:12) {
                            destinationChip("4 project tasks",icon:"folder")
                            destinationChip("5 Calendar entries",icon:"calendar")
                        }
                        Button {reviewOpen=true} label:{Label("Explore suggested actions",systemImage:"bubble.left.and.text.bubble.right")}.buttonStyle(.borderedProminent).controlSize(.large)
                        if let last=engine.visibleJobs.last {Button {activityOpen=true} label:{Label(last.status,systemImage:last.state == .partial ? "exclamationmark.circle" : "clock")}.buttonStyle(.borderless).font(.caption)}
                    } else {
                        Label("Missing plan",systemImage:"checklist").font(.caption).foregroundStyle(palette[.text].opacity(0.62))
                        Text("The project email says a hazard assessment form must be completed with your supervisor. I don’t see a clear date for the form.").lineSpacing(4)
                        Button("Review suggestion") {baselineOpen=true}.buttonStyle(.bordered)
                    }
                    DisclosureGroup("Source context") {
                        Text("Example schedule: Michaelmas presentations 26–27 November, 08:30–17:00; technical milestone report 21 January at 16:00; final report 31 May at 16:00; final presentation 4 June. Individual presentation slots are not supplied. No hazard-assessment deadline is given.").font(.callout).foregroundStyle(palette[.text].opacity(0.62)).padding(.top,8)
                    }.font(.caption)
                }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(palette[.widget],in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(palette[.border].opacity(0.4)))
                if trial {
                    HStack(alignment:.top,spacing:13) {
                        Image(systemName:"sparkles").foregroundStyle(palette[.accent]).font(.title3)
                        VStack(alignment:.leading,spacing:6) {Text("Reply here. Carry on elsewhere.").font(.headline);Text("Say yes or adjust the plan in Review. If a heartbeat is running, your request waits its turn. Follow the work and inspect any problem from the pill above.").foregroundStyle(palette[.text].opacity(0.62)).lineSpacing(3)}
                    }.padding(6)
                }
            }.padding(.bottom,4)
        }
    }
    private func destinationChip(_ text:String,icon:String)->some View {Label(text,systemImage:icon).font(.caption.weight(.medium)).padding(.horizontal,11).padding(.vertical,7).background(palette[.accent].opacity(0.1),in:Capsule())}
    private func results(_ actions:[ReviewTrialAction],empty:String)->some View {
        ScrollView {VStack(alignment:.leading,spacing:14) {
            if actions.isEmpty {ContentUnavailableView("Nothing added yet",systemImage:"folder.badge.plus",description:Text(empty)).frame(maxWidth:.infinity).padding(.top,70)}
            ForEach(actions) {action in HStack(alignment:.top,spacing:12) {Image(systemName:action.destination == .project ? "circle" : "calendar").foregroundStyle(palette[.accent]);VStack(alignment:.leading,spacing:5) {Text(action.title).font(.headline);Text(action.date).font(.callout);Text(action.detail).font(.caption).foregroundStyle(palette[.text].opacity(0.62))};Spacer();if action.provisional {Text("Provisional").font(.caption).padding(6).background(.orange.opacity(0.12),in:Capsule())}}.padding(18).background(palette[.widget],in:RoundedRectangle(cornerRadius:14))}
        }}
    }
    private var chatPage:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Hello. What would you like to work on?").padding(18).background(palette[.widget],in:RoundedRectangle(cornerRadius:16))
            Text("Your Review conversation stays with its suggestion. It does not appear in this general chat.").font(.callout).foregroundStyle(palette[.text].opacity(0.62))
            Spacer()
            Button("Return to Review conversation") {reviewOpen=true}.buttonStyle(.bordered)
        }
    }
    private var todayPage:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Your IIB dates are ready to organise.").font(.title2.weight(.semibold))
            Text("One project email has several useful milestones. Review the plan to put project work in its folder and dates in Calendar.").lineSpacing(4)
            Button("Open Review") {page="Review"}.buttonStyle(.borderedProminent)
            if engine.heartbeatTicks != nil {Text("A heartbeat is running. You can still submit a Review request.").foregroundStyle(palette[.text].opacity(0.62))}
            Spacer()
        }.padding(24).background(palette[.widget],in:RoundedRectangle(cornerRadius:18))
    }
    private var baselineSheet:some View {
        VStack(alignment:.leading,spacing:20) {
            Label("New reminder",systemImage:"checklist").font(.title2.weight(.semibold))
            Text("Complete and submit the hazard assessment with your supervisor.").foregroundStyle(.secondary)
            TextField("Title",text:.constant("Submit hazard assessment"))
            LabeledContent("List",value:"Example reminders")
            LabeledContent("Due",value:"None")
            LabeledContent("Repeat",value:"Never")
            Text("Notes").font(.headline)
            Text("The project email says this form is mandatory. No date is given in the example.").padding(14).frame(maxWidth:.infinity,minHeight:100,alignment:.topLeading).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
            Text("Illustrative baseline using example data.").font(.caption).foregroundStyle(.secondary)
            HStack {Button("Cancel"){baselineOpen=false};Spacer();Button("Create reminder (simulated)"){baselineOpen=false}}.padding(.top,12)
        }.padding(28).frame(width:520)
    }
}

struct ReviewTrialStatusPill:View {
    var engine:ReviewTrialEngine
    var palette:WorkspacePalette
    var openChat:()->Void
    var openActivity:()->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        HStack(spacing:0) {
            Button(action:openChat) {
                ZStack {
                    Circle().fill(palette[.accent].opacity(0.14))
                    if let progress=engine.progress {Circle().trim(from:0,to:max(0.035,progress)).stroke(palette[.accent],style:StrokeStyle(lineWidth:2.2,lineCap:.round)).rotationEffect(.degrees(-90))}
                    Image(systemName:"bubble.left.and.bubble.right.fill").font(.system(size:13)).foregroundStyle(palette[.accent])
                }.frame(width:32,height:32)
            }.buttonStyle(.plain).help("Open 3PO chat").accessibilityLabel("Open 3PO chat")
            Button(action:openActivity) {
                HStack(spacing:10) {
                    VStack(alignment:.leading,spacing:1) {
                        Text(engine.title).font(.system(size:12,weight:.semibold)).lineLimit(1)

                    }
                    Spacer(minLength:0)
                    Image(systemName:engine.attention != nil ? "exclamationmark.circle.fill" : engine.progress != nil ? "chevron.down" : engine.lastOutcome?.state == .succeeded ? "checkmark.circle.fill" : "chevron.down").font(.system(size:12)).foregroundStyle(engine.attention != nil ? Color.orange : palette[.accent])
                }.padding(.leading,9).padding(.trailing,8).frame(width:250)
            }.buttonStyle(.plain).help("Inspect current and queued AI jobs").accessibilityLabel("AI activity").accessibilityValue(engine.title)
        }.padding(4).background(palette[.widget].opacity(0.9),in:Capsule()).overlay(Capsule().stroke(engine.attention != nil ? .orange.opacity(0.5) : palette[.border].opacity(0.45),lineWidth:0.8))
            .animation(reduceMotion ? nil : .easeInOut(duration:0.3),value:engine.progress)
    }
}

struct ReviewTrialConversation:View {
    var engine:ReviewTrialEngine
    var palette:WorkspacePalette
    var height:CGFloat = 740
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                Image(systemName:"sparkles").font(.title2).foregroundStyle(palette[.accent])
                VStack(alignment:.leading,spacing:3) {Text("Plan your IIB dates").font(.title2.weight(.semibold));Text("Review conversation · stays with this suggestion").font(.caption).foregroundStyle(palette[.text].opacity(0.62))}
                Spacer();Button("Done") {dismiss()}.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            ScrollViewReader {proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        Text("This schedule belongs with your Cambridge Engineering IIB project. I suggest adding project tasks for the milestones, plus Calendar markers for the fixed dates.").lineSpacing(4)
                        Text("The November presentation window is provisional, not your personal slot. The hazard assessment has no date here, so I won’t invent a deadline. Check any existing hazard-assessment task separately.").font(.callout).foregroundStyle(palette[.text].opacity(0.62)).lineSpacing(3)
                        Text("Would you like me to add the selected actions below?").font(.headline)
                        VStack(alignment:.leading,spacing:12) {
                            actionGroup(.project,title:"In IIB MEng Project",icon:"folder")
                            Divider()
                            actionGroup(.calendar,title:"In Example Calendar",icon:"calendar")
                        }.padding(16).background(palette[.accent].opacity(0.045),in:RoundedRectangle(cornerRadius:14))
                        ForEach(engine.messages) {message in
                            HStack {
                                if message.human {Spacer(minLength:75)}
                                Text(message.text).font(.callout).lineSpacing(3).textSelection(.enabled).padding(14).background(message.human ? palette[.accent].opacity(0.17) : palette[.widget],in:RoundedRectangle(cornerRadius:13))
                                if !message.human {Spacer(minLength:30)}
                            }.id(message.id)
                        }
                        Color.clear.frame(height:1).id("end")
                    }.padding(22)
                }.onChange(of:engine.messages.count) {withAnimation {proxy.scrollTo("end",anchor:.bottom)}}
            }
            Divider()
            VStack(alignment:.leading,spacing:10) {
                if let job=engine.visibleJobs.last {Label(job.status,systemImage:job.state == .queued ? "clock" : job.state == .partial ? "exclamationmark.circle" : "sparkles").font(.caption).foregroundStyle(job.state == .partial ? Color.orange : palette[.text].opacity(0.62))}
                HStack(spacing:10) {
                    TextField("Say yes, choose actions, or ask for a change…",text:$draft,axis:.vertical).textFieldStyle(.plain).lineLimit(1...4).padding(12).background(palette[.widget],in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(palette[.border].opacity(0.45))).onSubmit(send)
                    Button(action:send) {Image(systemName:"arrow.up").font(.headline).frame(width:34,height:34)}.buttonStyle(.borderedProminent).clipShape(Circle()).disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityLabel("Send Review reply")
                }
                Text("Try ‘yes’, ‘project tasks only’, ‘calendar only’, or ‘leave November out’. Jobs are simulated.").font(.caption2).foregroundStyle(palette[.text].opacity(0.62))
            }.padding(18)
        }.frame(width:740,height:height).background(palette[.canvas]).foregroundStyle(palette[.text]).tint(palette[.accent])
    }
    private func send() {guard !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return};_ = engine.submit(draft);draft=""}
    private func actionGroup(_ destination:ReviewTrialAction.Destination,title:String,icon:String)->some View {
        VStack(alignment:.leading,spacing:10) {
            Label(title,systemImage:icon).font(.callout.weight(.semibold)).foregroundStyle(palette[.accent])
            ForEach(ReviewTrialAction.examples.filter{$0.destination == destination}) {action in
                Toggle(isOn:Binding(get:{engine.selection.contains(action.id)},set:{if $0 {engine.selection.insert(action.id)} else {engine.selection.remove(action.id)}})) {
                    VStack(alignment:.leading,spacing:3) {Text(action.title).font(.callout.weight(.medium));Text(action.date).font(.caption).foregroundStyle(palette[.text].opacity(0.62));if action.provisional {Text("Provisional window").font(.caption2).foregroundStyle(.orange)}}
                }.toggleStyle(.checkbox).help(action.detail)
            }
        }
    }
}

struct ReviewTrialActivity:View {
    var engine:ReviewTrialEngine
    var openReview:()->Void
    var openResults:()->Void
    @Environment(\.workspacePalette) private var palette
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("AI activity").font(.title3.weight(.semibold))
            if engine.heartbeatTicks != nil {
                VStack(alignment:.leading,spacing:7) {Label("Heartbeat",systemImage:"waveform.path.ecg").font(.headline);Text(engine.heartbeatStage).font(.callout);ProgressView(value:engine.heartbeatProgress);Text("\(Int(engine.heartbeatProgress*100))% · requests wait until this finishes").font(.caption).foregroundStyle(.secondary)}
            }
            if engine.visibleJobs.isEmpty {Text("No Review jobs yet. Open a suggestion and reply to its plan.").font(.callout).foregroundStyle(.secondary)}
            ScrollView {VStack(alignment:.leading,spacing:16) {
                ForEach(engine.visibleJobs.reversed()) {job in
                    VStack(alignment:.leading,spacing:8) {
                        HStack {Text(job.title).font(.headline);Spacer();Text(job.state.rawValue.capitalized).font(.caption).foregroundStyle(job.state == .partial || job.state == .failed ? Color.orange : .secondary)}
                        Text(job.status).font(.callout)
                        if let error=job.error {Text(error).font(.caption).foregroundStyle(.orange)}
                        if job.state == .running {ProgressView(value:job.progress)}
                        ForEach(job.actions.filter{job.outcomes[$0.id] == .uncertain}) {action in
                            VStack(alignment:.leading,spacing:6) {Label(action.title,systemImage:"exclamationmark.circle").font(.callout);Text(action.date).font(.caption);Button("Check example Calendar save") {engine.checkUncertain(job.id,actionID:action.id)}.controlSize(.small)}
                        }
                        HStack {
                            Button("Open conversation",action:openReview)
                            if job.state == .succeeded {Button("View project",action:openResults)}
                            if [.partial,.failed,.stopped,.succeeded].contains(job.state) && !job.acknowledged {Button("Acknowledge") {engine.acknowledge(job.id)}}
                        }.controlSize(.small)
                    }.padding(13).background(palette[.accent].opacity(0.06),in:RoundedRectangle(cornerRadius:12))
                }
            }}.frame(maxHeight:310)
            HStack {if engine.heartbeatTicks != nil || engine.activeJobID != nil {Button("Stop current job") {engine.stop()}};if engine.paused && engine.queuedCount > 0 {Button("Continue queue") {engine.continueQueue()}};Spacer()}
            Text("Demo activity is kept while this window is open. Relaunching resets the example.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
#endif
