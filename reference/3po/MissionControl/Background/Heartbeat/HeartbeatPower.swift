import Foundation
import IOKit
import IOKit.pwr_mgt

struct HeartbeatDeviceState: Equatable {
    var lidClosed: Bool
    var userWake: Bool
    var available: Bool { !lidClosed && userWake }
    static func current() -> Self {
        let root=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return .init(lidClosed:false,userWake:false) }
        defer { IOObjectRelease(root) }
        let lid=IORegistryEntryCreateCFProperty(root,"AppleClamshellState" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? Bool ?? false
        // Apple's root-domain implementation publishes its current capabilities.
        // A dark wake lacks Graphics. Display sleep alone is not a lid closure.
        let capabilities=IORegistryEntryCreateCFProperty(root,"System Capabilities" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber
        let required=UInt32(kIOPMSystemCapabilityCPU | kIOPMSystemCapabilityGraphics)
        return .init(lidClosed:lid,userWake:capabilities.map{($0.uint32Value & required) == required} ?? false)
    }
}

@MainActor final class HeartbeatPowerMonitor {
    private var port: IONotificationPortRef?
    private var notification: io_object_t = 0
    private let changed: @MainActor () -> Void
    init(changed:@escaping @MainActor ()->Void) {
        self.changed=changed
        let root=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return }
        defer { IOObjectRelease(root) }
        guard let port=IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port=port
        IONotificationPortSetDispatchQueue(port,DispatchQueue.main)
        // General-interest notifications include lid changes before ensuing sleep.
        // Treat every hint as a fresh state read, never as proof of availability.
        IOServiceAddInterestNotification(port,root,kIOGeneralInterest,{ context,_,_,_ in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<HeartbeatPowerMonitor>.fromOpaque(context).takeUnretainedValue().changed()
            }
        },Unmanaged.passUnretained(self).toOpaque(),&notification)
    }
    deinit {
        if notification != 0 { IOObjectRelease(notification) }
        if let port { IONotificationPortDestroy(port) }
    }
}
