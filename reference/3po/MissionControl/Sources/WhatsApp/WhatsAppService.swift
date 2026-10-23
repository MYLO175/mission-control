import SwiftUI
import AppKit
import Security
import CryptoKit

@MainActor @Observable final class WhatsAppService {
    var status = "Not connected"
    var reconnectAtLaunch = UserDefaults.standard.bool(forKey:"whatsappReconnectAtLaunch") {
        didSet { if !disposable { UserDefaults.standard.set(reconnectAtLaunch,forKey:"whatsappReconnectAtLaunch") } }
    }
    var connected = false
    var namesBusy=false
    var namesStatus=""
    var qr: NSImage?
    var messages: [WhatsAppReadMessage] = [] {
        didSet { windowFingerprints.removeAll(keepingCapacity:true) }
    }
    var chats: [WhatsAppChat] = []
    var linkedIdentity = "" {
        didSet { windowFingerprints.removeAll(keepingCapacity:true);if linkedIdentity != oldValue {readAccessRevisions.invalidateIdentity()} }
    }
    @ObservationIgnored private var windowFingerprints:[String:String]=[:]
    #if DEBUG
    @ObservationIgnored private(set) var windowFingerprintBuilds=0
    #endif
    /// Derived hashes only; permissions and ownership are checked by each caller.
    /// Read both observed inputs even on a hit so mounted views track invalidation.
    func windowFingerprint(chat:String)->String {
        let currentMessages=messages,identity=linkedIdentity
        if let saved=windowFingerprints[chat] {return saved}
        let value=ProactiveRules.whatsappWindow(currentMessages,chats:[chat],identity:identity)
        if windowFingerprints.count >= 64 {windowFingerprints.removeAll(keepingCapacity:true)}
        windowFingerprints[chat]=value
        #if DEBUG
        windowFingerprintBuilds+=1
        #endif
        return value
    }
    var accessRevision = UUID()
    private(set) var choicesRevision = UUID()
    @ObservationIgnored private var readAccessRevisions=WhatsAppReadAccessRevisions()
    private var accesses: [String:WhatsAppAccess] = [:]
    var coverage = "No WhatsApp data received."
    #if DEBUG
    func seedReviewSourceFixture(_ message:WhatsAppReadMessage,registration:String) {
        guard ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"),ProcessInfo.processInfo.arguments.contains("--source-details-preview") else {return}
        linkedIdentity="fictional-review-device";messages=[message];chats=[.init(id:message.chat,name:"Orion project group",group:true)]
        if let key=WhatsAppReadRules.accessKey(registration:registration,linkedIdentity:linkedIdentity) {accesses=[key:.init(enabled:true,chats:[message.chat],includeInSuggestions:true)]}
        // In-memory fixture only: no helper start, Keychain, encrypted access save or permission change.
    }
    #endif
    private var process: Process?
    private var input: FileHandle?
    private var reader: WhatsAppOutputReader?
    private var generation=UUID()
    private var snapshotID: String?
    private var disposable = false
    private let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Mission Control/WhatsApp",isDirectory:true)
    private let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.mylomichael.missioncontrol.whatsapp",kSecAttrAccount as String:"session-encryption"]
    private func key() throws -> Data {
        guard !disposable else { throw CocoaError(.featureUnsupported) }
        var request=query; request[kSecReturnData as String]=true
        var result: CFTypeRef?
        let found=SecItemCopyMatching(request as CFDictionary,&result)
        if found == errSecSuccess, let data=result as? Data { return data }
        guard found == errSecItemNotFound else { throw CocoaError(.fileReadNoPermission) }
        let data=SymmetricKey(size:.bits256).withUnsafeBytes { Data($0) }
        var item=query; item[kSecValueData as String]=data; item[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary,nil)==errSecSuccess else { throw CocoaError(.fileWriteNoPermission) }
        return data
    }
    init() {
        if ProcessInfo.processInfo.arguments.contains("--sample") { disposable = true; return }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let fictionalModes: Set<String> = ["--validate-advice-context", "--validate-review-inbox", "--validate-native-memory", "--validate-commitment-reports", "--validate-memory-inspection", "--validate-source-timeline", "--render-projects"]
        if arguments.contains(where: { fictionalModes.contains($0) || $0.hasPrefix("--preview-") }) {
            disposable = true
            return // Before personal encrypted access data or Keychain is opened.
        }
        #endif
        let path=directory.appendingPathComponent("access.enc")
        if let bytes=try? Data(contentsOf:path) {
            do { let decrypted=try AES.GCM.open(AES.GCM.SealedBox(combined:bytes),using:SymmetricKey(data:try key())); accesses=try JSONDecoder().decode([String:WhatsAppAccess].self,from:decrypted) }
            catch { status="WhatsApp access preferences could not be read. AI access stays off." }
        }
    }
    func access(for registration: String) -> WhatsAppAccess {
        WhatsAppReadRules.access(accesses,registration:registration,linkedIdentity:linkedIdentity)
    }
    func scope(for registration: String) -> WhatsAppSourceScope {
        .init(registration:registration,linkedIdentity:linkedIdentity,revision:accessRevision)
    }
    func scope(for registration:String,purpose:WhatsAppReadPurpose)->WhatsAppSourceScope {
        let key=WhatsAppReadRules.accessKey(registration:registration,linkedIdentity:linkedIdentity) ?? registration
        return .init(registration:registration,linkedIdentity:linkedIdentity,revision:readAccessRevisions.revision(key:key,purpose:purpose),identityRevision:readAccessRevisions.identityRevision)
    }
    func setAccess(_ access: WhatsAppAccess, registration: String) {
        guard let id=WhatsAppReadRules.accessKey(registration:registration,linkedIdentity:linkedIdentity) else { return }
        let previous=accesses[id] ?? .init(),revised=WhatsAppReadRules.recordingLearningAccess(access,previous:previous)
        guard revised != previous else {return}
        var updated=accesses
        updated[id]=revised
        if disposable {
            accesses=updated;accessRevision=UUID();choicesRevision=UUID()
            readAccessRevisions.record(key:id,previous:previous,current:revised)
            return
        }
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let bytes=try JSONEncoder().encode(updated)
            let sealed=try AES.GCM.seal(bytes,using:SymmetricKey(data:try key())).combined!
            let path=directory.appendingPathComponent("access.enc")
            try sealed.write(to:path,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
            accesses=updated;accessRevision=UUID();choicesRevision=UUID()
            readAccessRevisions.record(key:id,previous:previous,current:revised)
        } catch { status="Could not save WhatsApp source choices; previous choices retained." }
    }
    func refreshSnapshot() async -> Bool {
        guard connected,let input else { return false }
        let request=UUID().uuidString,owner=generation
        do {
            try input.write(contentsOf:JSONSerialization.data(withJSONObject:["action":"snapshot","requestID":request])+Data([10]))
            let deadline=Date.now.addingTimeInterval(5)
            while Date.now < deadline,connected,generation == owner {
                try Task.checkCancellation()
                if snapshotID == request { return true }
                try await Task.sleep(for:.milliseconds(50))
            }
        } catch { return false }
        return false
    }
    func refreshNames() {
        guard connected,!namesBusy else { return }
        do { try input?.write(contentsOf:JSONSerialization.data(withJSONObject:["action":"refresh-names"])+Data([10])) }
        catch { namesStatus="Could not request contact names. Reconnect and try again." }
    }
    func resumeAtLaunch() {
        guard !disposable else { return }
        if reconnectAtLaunch && FileManager.default.fileExists(atPath:directory.appendingPathComponent("auth.enc").path) { connect() }
    }
    func connect() {
        guard !disposable else { status="WhatsApp is isolated in this fictional preview or evaluation."; return }
        guard !ProcessInfo.processInfo.arguments.contains("--sample") else { status="WhatsApp is unavailable in sample mode."; return }
        if process != nil { if connected || qr != nil { return }; stop(persistPause:false) }
        guard let root=Bundle.main.resourceURL?.appendingPathComponent("WhatsAppBridge"), FileManager.default.fileExists(atPath:root.appendingPathComponent("reader.mjs").path) else { status="WhatsApp helper is missing from this build."; return }
        guard let node=[root.appendingPathComponent("Runtime/node").path,"/usr/local/bin/node","/opt/homebrew/bin/node"].first(where:{ FileManager.default.isExecutableFile(atPath:$0) }) else { status="This experimental connector requires Node.js 20 or later installed on this Mac."; return }
        do {
            let secret=try key(), task=Process(), incoming=Pipe(), outgoing=Pipe()
            // Cached text arriving from the helper is not AI-eligible until this
            // process has authenticated its own linked identity.
            linkedIdentity=""; accessRevision=UUID()
            let token=UUID(); generation=token
            task.environment=ProcessInfo.processInfo.environment.filter { !["NODE_OPTIONS","NODE_PATH","NODE_TLS_REJECT_UNAUTHORIZED","SSLKEYLOGFILE"].contains($0.key) && !$0.key.hasPrefix("DYLD_") }
            task.executableURL=URL(fileURLWithPath:node); task.arguments=[root.appendingPathComponent("reader.mjs").path]
            task.standardInput=incoming; task.standardOutput=outgoing; task.standardError=FileHandle.nullDevice
            let receiver=WhatsAppOutputReader { [weak self] data in Task { @MainActor in if self?.generation == token { self?.receive(data) } } }
            outgoing.fileHandleForReading.readabilityHandler={ handle in let data=handle.availableData; if data.isEmpty { handle.readabilityHandler=nil } else { receiver.read(data) } }
            task.terminationHandler={ [weak self] _ in Task { @MainActor in
                guard let self, self.generation == token else { return }
                let unexpected=self.connected || self.status == "Connecting…" || self.status == "Reconnecting…"
                self.process=nil; self.namesBusy=false; self.connected=false; self.qr=nil; self.input=nil; self.reader=nil
                if unexpected { self.status="Stopped · reconnect to resume reading" }
            } }

            try task.run(); process=task; input=incoming.fileHandleForWriting; reader=receiver; status="Connecting…"
            let command:[String:String]=["action":"start","directory":directory.path,"key":secret.base64EncodedString()]
            try input?.write(contentsOf:JSONSerialization.data(withJSONObject:command)+Data([10]))
        } catch { stop(); status="Cannot start WhatsApp or access its encrypted session." }
    }
    func stop(persistPause: Bool = true) { if persistPause { reconnectAtLaunch=false }; generation=UUID(); process?.terminationHandler=nil; input?.closeFile(); process?.terminate(); process=nil; input=nil; reader=nil; namesBusy=false; connected=false; qr=nil; status="Paused · session retained" }
    func disconnect() {
        stop(); messages=[]; chats=[]; accesses=[:]; linkedIdentity="";accessRevision=UUID();choicesRevision=UUID()
        if disposable { status="Fictional source disconnected."; return }
        do {
            if FileManager.default.fileExists(atPath:directory.path) { try FileManager.default.removeItem(at:directory) }
            let result=SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { throw CocoaError(.fileWriteNoPermission) }
            status="Disconnected · also remove 3PO from WhatsApp’s Linked devices."
        } catch { status="PA access stopped, but local session cleanup failed. Try Disconnect again." }
    }
    private func receive(_ event: WhatsAppReadEvent) {
        guard process != nil else { return }
        if let id=event.snapshotID { snapshotID=id }
        if event.revoked == true { linkedIdentity=""; accessRevision=UUID() }
        if let identity=event.identity, identity != linkedIdentity { linkedIdentity=identity; accessRevision=UUID() }
        if let busy=event.namesBusy { namesBusy=busy }
        if let status=event.namesStatus { namesStatus=status }
        if let values=event.chats { chats=values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        if let value=event.status { status=value }
        if let value=event.connected { connected=value; if value || status.contains("revoked") { qr=nil } }
        if let png=event.png, let encoded=png.split(separator:",").last, let image=Data(base64Encoded:String(encoded)) { qr=NSImage(data:image) }
        if let values=event.messages { messages=values }
        if let value=event.coverage { coverage=value }
    }

}
private final class WhatsAppOutputReader: @unchecked Sendable {
    private let lock=NSLock()
    private var buffer=Data()
    private let deliver: (WhatsAppReadEvent)->Void
    init(deliver:@escaping(WhatsAppReadEvent)->Void) { self.deliver=deliver }
    func read(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }; buffer.append(data)
        guard buffer.count < 40_000_000 else { buffer.removeAll(); return }
        while let newline=buffer.firstIndex(of:10) { let line=Data(buffer[..<newline]); buffer.removeSubrange(...newline); if let event=try? JSONDecoder().decode(WhatsAppReadEvent.self,from:line) { deliver(event) } }
    }
}
struct WhatsAppSettings: View {
    @Bindable var service: WhatsAppService
    let registration: String
    var heartbeatReviewEnabled=false
    @State private var showMessages=false
    @State private var showSources=false
    @State private var viewerChat=""
    @State private var viewerQuery=""
    var body: some View {
        Section("WhatsApp linked device · read-only") {
            Text("Link through a QR code as another device. This uses an unofficial WhatsApp Web connection; WhatsApp changes or account restrictions may interrupt it. No sending or read receipts. Reception makes no AI requests. Sessions and received text are encrypted locally; the encryption key stays in Keychain.").font(.caption).foregroundStyle(.secondary)
            Toggle("Reconnect WhatsApp when 3PO launches",isOn:$service.reconnectAtLaunch)
            Text(service.status)
            if let qr=service.qr { Image(nsImage:qr).resizable().interpolation(.none).frame(width:240,height:240); Text("On your phone: WhatsApp → Settings → Linked devices → Link a device. Scan this code only if you want 3PO to receive your chats.").font(.caption) }
            HStack { Button("Connect / show QR") { service.connect() }; Button("Pause") { service.stop() }; Button("Disconnect") { service.disconnect() }; Button("Received text (\(service.messages.count))") { showMessages=true } }
            Button("PA chat access…") { showSources=true }.disabled(service.linkedIdentity.isEmpty)
            Text("Only selected chats with PA access can be reviewed. Review access also permits useful memory learning, controlled by Allow memory learning in Memory settings.").font(.caption).foregroundStyle(.secondary)
            WhatsAppSourceSummary(service:service,registration:registration,heartbeatReviewEnabled:heartbeatReviewEnabled)
            Text(service.coverage).font(.caption).foregroundStyle(.secondary)
        }.sheet(isPresented:$showSources) {
            WhatsAppSourcePicker(service:service,registration:registration,heartbeatReviewEnabled:heartbeatReviewEnabled)
        }.sheet(isPresented:$showMessages) {
            VStack(alignment:.leading) {
                HStack { Text("WhatsApp received text").font(.title2); Spacer(); Button("Done") { showMessages=false } }
                Text(service.coverage).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("Chat",selection:$viewerChat) { Text("All received chats").tag(""); ForEach(service.chats) { Text($0.name).tag($0.id) } }.frame(maxWidth:250)
                    TextField("Search received text",text:$viewerQuery)
                }
                List(service.messages.filter { (viewerChat.isEmpty || $0.chat == viewerChat) && (viewerQuery.isEmpty || ($0.text + " " + $0.sender).localizedCaseInsensitiveContains(viewerQuery)) }) { message in VStack(alignment:.leading,spacing:4) { Text(message.sender).font(.headline); Text(service.chats.first(where:{$0.id == message.chat})?.name ?? message.chat).font(.caption).foregroundStyle(.secondary); Text(message.text).textSelection(.enabled); Text(Date(timeIntervalSince1970:message.time/1000),style:.date).font(.caption).foregroundStyle(.secondary) } }
            }.padding(20).frame(width:650,height:550)
        }
    }
}

struct WhatsAppBriefSource: View {
    @Bindable var service: WhatsAppService
    let registration: String
    let source: BriefingSource
    @State private var showing=false
    private var message: WhatsAppReadMessage? {
        let access=service.access(for:registration)
        guard access.briefEnabled, source.linkedIdentity == service.linkedIdentity,
              let chat=source.chatID, access.chats.contains(chat) else { return nil }
        return service.messages.first { $0.id == source.originalID && $0.chat == chat }
    }
    var body: some View {
        Button(source.label) { showing=true }.buttonStyle(.link).font(.caption).disabled(message == nil)
            .help(message == nil ? "Source is excluded or no longer in the received cache" : "Read the cached WhatsApp source; no read receipt")
            .sheet(isPresented:$showing) {
                VStack(alignment:.leading,spacing:14) {
                    HStack { Label("WhatsApp source",systemImage:"bubble.left").font(.headline); Spacer(); Button("Done") { showing=false } }
                    if let message {
                        Text(source.label).foregroundStyle(.secondary)
                        Text(message.sentByMe ? "You" : message.sender).font(.headline)
                        Text(Date(timeIntervalSince1970:message.time/1000).formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                        ScrollView { Text(message.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
                        Text("Received cache · may have changed since the brief was prepared · no read receipt").font(.caption).foregroundStyle(.secondary)
                    } else { ContentUnavailableView("Source unavailable",systemImage:"bubble.left",description:Text("This chat is excluded, belongs to another linked account, or the message left the received cache.")) }
                }.padding(20).frame(width:550,height:400)
            }
    }
}
