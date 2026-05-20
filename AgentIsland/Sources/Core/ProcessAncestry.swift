import AppKit
import Darwin

enum ProcessAncestry {

    static func findTerminalAppPID(of agentPID: pid_t) -> pid_t? {
        let runningAppPIDs = Set(
            NSWorkspace.shared.runningApplications.map { $0.processIdentifier }
        )

        var current = agentPID
        for _ in 0..<20 {
            guard let parent = parentPID(of: current), parent > 1 else { return nil }
            if runningAppPIDs.contains(parent) { return parent }
            current = parent
        }
        return nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }
}
