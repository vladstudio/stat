import Foundation
import IOKit
import os
import CIOHIDPrivate

// kIOHIDEventTypeTemperature (Apple vendor page, undocumented)
private let kIOHIDEventTypeTemperature: Int64 = 15

private let log = Logger(subsystem: "studio.vlad.stat", category: "SystemStats")

public struct Stats: Sendable {
    public init() {}

    public var cpuLoad: Int = 0
    public var gpuLoad: Int = 0
    public var temperature: Int = 0
    public var downloadBytesPerSec: UInt64 = 0
    public var uploadBytesPerSec: UInt64 = 0

    public var downloadDisplay: (value: String, isMega: Bool) {
        let kbps = downloadBytesPerSec / 1024
        if kbps >= 1000 {
            return (String(format: "%.2f", Double(kbps) / 1024.0), true)
        }
        return ("\(kbps)", false)
    }

    public var uploadDisplay: (value: String, isMega: Bool) {
        let kbps = uploadBytesPerSec / 1024
        if kbps >= 1000 {
            return (String(format: "%.2f", Double(kbps) / 1024.0), true)
        }
        return ("\(kbps)", false)
    }
}

/// Actor: read() is invoked from the menu bar UI but runs its syscalls
/// off the main thread; no state is shared with callers.
public actor SystemStats {
    private var prevCPUTicks: [pid_t: UInt64] = [:]
    private var prevCPUWall: UInt64 = 0
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var hasBaseline = false

    // Client must stay alive for the service clients to remain valid.
    private let tempClient: AnyObject?
    private let tempServices: [AnyObject]

    public init() {
        let matching: [String: Any] = [
            "PrimaryUsagePage": 0xff00,
            "PrimaryUsage": 0x0005,
        ]
        let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        var sensors: [AnyObject] = []
        if let client {
            _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
            if let all = IOHIDEventSystemClientCopyServices(client) as? [AnyObject] {
                sensors = all.filter { svc in
                    guard let name = IOHIDServiceClientCopyProperty(svc, "Product" as CFString) as? String else { return false }
                    // M3/M4 die-area sensors + M1/M2 per-cluster sensors.
                    return name.hasPrefix("PMU tdie")
                        || name.hasPrefix("pACC MTR")
                        || name.hasPrefix("eACC MTR")
                        || name.hasPrefix("GPU MTR")
                }
            }
        }
        if sensors.isEmpty { log.error("no temperature sensors matched — temperature will read 0") }
        self.tempClient = client
        self.tempServices = sensors
    }

    public func invalidateBaseline() {
        hasBaseline = false
        prevCPUTicks.removeAll()
        prevCPUWall = 0
    }

    public func read() -> Stats {
        var stats = Stats()
        stats.cpuLoad = readCPU()
        stats.gpuLoad = readGPU()
        stats.temperature = readTemperature()
        let (netIn, netOut) = readNetBytes()
        if hasBaseline {
            stats.downloadBytesPerSec = netIn > prevNetIn ? netIn - prevNetIn : 0
            stats.uploadBytesPerSec = netOut > prevNetOut ? netOut - prevNetOut : 0
        }
        prevNetIn = netIn
        prevNetOut = netOut
        hasBaseline = true
        log.debug("cpu=\(stats.cpuLoad) gpu=\(stats.gpuLoad) temp=\(stats.temperature) down=\(stats.downloadBytesPerSec) up=\(stats.uploadBytesPerSec)")
        return stats
    }

    // MARK: - CPU (top process %)

    /// One process's CPU % over the wall-time window. A recycled PID reports
    /// fewer ticks than its predecessor — clamped to 0 to avoid UInt64 underflow.
    static func cpuPercent(total: UInt64, prev: UInt64, wallDelta: UInt64) -> Int {
        let delta = total > prev ? total - prev : 0
        guard wallDelta > 0, delta > 0, delta < wallDelta * 64 else { return 0 }
        return Int((Double(delta) / Double(wallDelta)) * 100)
    }

    private func readCPU() -> Int {
        let now = mach_absolute_time()
        let wallDelta = now - prevCPUWall

        let bufSize = proc_listallpids(nil, 0)
        guard bufSize > 0 else { return 0 }
        let buf = UnsafeMutablePointer<pid_t>.allocate(capacity: Int(bufSize))
        defer { buf.deallocate() }
        let listed = proc_listallpids(buf, bufSize)
        guard listed > 0 else {
            log.error("proc_listallpids: \(listed)")
            return 0
        }
        // The pid list can grow between the two calls — clamp to the allocation.
        let count = min(listed, bufSize)

        // First call — establish baseline
        guard prevCPUWall > 0, wallDelta > 0 else {
            for i in 0..<Int(count) {
                let pid = buf[i]
                guard pid > 0 else { continue }
                var info = proc_taskinfo()
                let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.stride))
                guard size > 0 else { continue }
                prevCPUTicks[pid] = info.pti_total_user + info.pti_total_system
            }
            prevCPUWall = now
            return 0
        }

        var maxPct = 0
        var seen = Set<pid_t>()

        for i in 0..<Int(count) {
            let pid = buf[i]
            guard pid > 0 else { continue }
            seen.insert(pid)

            var info = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.stride))
            guard size > 0 else { continue }

            let total = info.pti_total_user + info.pti_total_system
            if let prev = prevCPUTicks[pid] {
                let pct = Self.cpuPercent(total: total, prev: prev, wallDelta: wallDelta)
                if pct > maxPct { maxPct = pct }
            }
            prevCPUTicks[pid] = total
        }

        // Remove zombie PIDs
        for pid in prevCPUTicks.keys where !seen.contains(pid) {
            prevCPUTicks.removeValue(forKey: pid)
        }

        prevCPUWall = now
        return maxPct
    }

    // MARK: - GPU (aggregate utilization)
    // Per-process GPU % is not available through public APIs on macOS.
    // We read the aggregate GPU Device Utilization % from IOAccelerator.

    private func readGPU() -> Int {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var maxPct = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                let pct = Self.gpuUtil(from: perfStats)
                if pct > maxPct { maxPct = pct }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return maxPct
    }

    /// IOAccelerator stats keys are undocumented and vary by GPU generation — try known keys, then anything utilization-shaped.
    static func gpuUtil(from stats: [String: Any]) -> Int {
        if let v = stats["GPU Activity(%)"] as? Int { return v }
        if let v = stats["Device Utilization %"] as? Int { return v }
        if let v = stats["GPU Core Utilization"] as? Int { return v }
        if let v = stats["gpuCoreUtilizationComponent"] as? Int { return v / 1_000_000 }
        for (key, value) in stats where key.contains("tilization") || key.contains("Activity") {
            if let v = value as? Int { return v > 100_000 ? v / 1_000_000 : v }
        }
        return 0
    }

    // MARK: - Temperature

    private func readTemperature() -> Int {
        var maxTemp: Double = 0
        for svc in tempServices {
            guard let event = IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let t = IOHIDEventGetFloatValue(event, Int32(kIOHIDEventTypeTemperature << 16))
            if t > -100, t < 200, t > maxTemp { maxTemp = t }
        }
        return Int(maxTemp.rounded())
    }

    // MARK: - Network

    private func readNetBytes() -> (UInt64, UInt64) {
        var mib = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: size_t = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else {
            log.error("sysctl iflist size: \(String(cString: strerror(errno)))")
            return (0, 0)
        }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
        defer { buf.deallocate() }
        guard sysctl(&mib, 6, buf, &len, nil, 0) == 0 else {
            log.error("sysctl iflist: \(String(cString: strerror(errno)))")
            return (0, 0)
        }

        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        var ptr = UnsafeMutableRawPointer(buf)
        let end = ptr + len
        while ptr < end {
            let hdr = ptr.assumingMemoryBound(to: if_msghdr.self).pointee
            guard hdr.ifm_msglen > 0 else { break } // zero-length message would spin forever
            if hdr.ifm_type == RTM_IFINFO2 {
                let hdr2 = ptr.assumingMemoryBound(to: if_msghdr2.self).pointee
                // All non-loopback interfaces — VPN tunnels double-count their underlying interface
                if hdr2.ifm_data.ifi_type != UInt8(IFT_LOOP) {
                    totalIn += hdr2.ifm_data.ifi_ibytes
                    totalOut += hdr2.ifm_data.ifi_obytes
                }
            }
            ptr += Int(hdr.ifm_msglen)
        }
        return (totalIn, totalOut)
    }
}