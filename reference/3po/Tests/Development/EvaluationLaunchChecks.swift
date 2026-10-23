import Foundation

@main struct EvaluationLaunchChecks {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool) { precondition(condition); count += 1 }
        check(EvaluationLaunchGuard.decision(arguments:["3PO"], isDebug:false) == .proceed)
        check(EvaluationLaunchGuard.decision(arguments:["3PO", "--small-window"], isDebug:true) == .proceed)
        for debug in [false, true] {
            guard case .exit(let code, let output) = EvaluationLaunchGuard.decision(arguments:["3PO", "--evaluation-handshake"], isDebug:debug) else { preconditionFailure() }
            let value = try JSONSerialization.jsonObject(with:Data(output.utf8)) as! [String:Any]
            check(code == 0 && value["protocol"] as? Int == 1 && value["debug"] as? Bool == debug)
            check(value["bundleID"] as? String == "com.mylomichael.missioncontrol")
            check((value["modes"] as? [[String]]) == (debug ? EvaluationLaunchGuard.modes : []))
        }
        for mode in EvaluationLaunchGuard.modes {
            check(EvaluationLaunchGuard.decision(arguments:["3PO"] + mode, isDebug:true) == .proceed)
            guard case .exit(let code,_) = EvaluationLaunchGuard.decision(arguments:["3PO"] + mode, isDebug:false) else { preconditionFailure("Release must fail before services") }
            check(code != 0)
        }
        for flag in ["--validate-unknown", "--preview-unknown", "--render-unknown", "--evaluation-unknown", "--inspect-unknown", "--cleanup-unknown"] {
            guard case .exit(let code,_) = EvaluationLaunchGuard.decision(arguments:["3PO",flag], isDebug:true) else { preconditionFailure("Unknown mode must fail before services") }
            check(code != 0)
        }
        for flag in ["--inspect-luna-access","--cleanup-request-markers"] {
            check(EvaluationLaunchGuard.decision(arguments:["3PO",flag],isDebug:true) == .proceed)
            guard case .exit(let code,_) = EvaluationLaunchGuard.decision(arguments:["3PO",flag],isDebug:false) else {preconditionFailure("Release diagnostics must refuse before services")}
            check(code != 0)
        }
        guard case .exit(let conflict,_) = EvaluationLaunchGuard.decision(arguments:["3PO","--validate-advice-context","--preview-projects"], isDebug:true) else { preconditionFailure() }
        check(conflict != 0)
        print("PASS \(count) evaluation startup checks: early Debug/Release handshake and mode refusal before service construction.")
    }
}
