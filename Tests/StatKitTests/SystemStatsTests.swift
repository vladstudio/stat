import Testing
@testable import StatKit

@Test func cpuPercentClampsRecycledPid() {
    // Regression: PID reuse made total < prev → UInt64 underflow crashed the app at login
    #expect(SystemStats.cpuPercent(total: 100, prev: 500, wallDelta: 1_000_000) == 0)
}

@Test func cpuPercent() {
    #expect(SystemStats.cpuPercent(total: 1_100_000, prev: 100_000, wallDelta: 10_000_000) == 10)
    #expect(SystemStats.cpuPercent(total: 100, prev: 100, wallDelta: 1_000_000) == 0)
    #expect(SystemStats.cpuPercent(total: 100, prev: 0, wallDelta: 0) == 0)
}

@Test func gpuUtilHeuristics() {
    #expect(SystemStats.gpuUtil(from: ["Device Utilization %": 42]) == 42)
    #expect(SystemStats.gpuUtil(from: ["gpuCoreUtilizationComponent": 42_000_000]) == 42)
    #expect(SystemStats.gpuUtil(from: ["Some Utilization Weird": 73]) == 73)
    #expect(SystemStats.gpuUtil(from: ["Unknown Key": 1]) == 0)
}

@Test func netDisplay() {
    var stats = Stats()
    stats.downloadBytesPerSec = 1_500_000
    stats.uploadBytesPerSec = 4096
    #expect(stats.downloadDisplay == ("1.43", true))
    #expect(stats.uploadDisplay == ("4", false))
}