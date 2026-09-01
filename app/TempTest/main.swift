#if DEBUG
import Foundation
import CIOHIDPrivate

let kHIDPage_AppleVendor = 0xff00
let kHIDUsage_AppleVendor_TemperatureSensor = 0x0005
let kIOHIDEventTypeTemperature: Int64 = 15

let matching: [String: Any] = [
    "PrimaryUsagePage": kHIDPage_AppleVendor,
    "PrimaryUsage": kHIDUsage_AppleVendor_TemperatureSensor,
]

guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
    fputs("error: IOHIDEventSystemClientCreate returned nil\n", stderr)
    exit(1)
}

_ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)

guard let services = IOHIDEventSystemClientCopyServices(client) as? [AnyObject] else {
    fputs("error: no services\n", stderr)
    exit(1)
}

struct Reading { let name: String; let temp: Double }
var readings: [Reading] = []

for svc in services {
    let name = (IOHIDServiceClientCopyProperty(svc, "Product" as CFString) as? String) ?? "<unknown>"
    guard let event = IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0) else { continue }
    let temp = IOHIDEventGetFloatValue(event, Int32(kIOHIDEventTypeTemperature << 16))
    readings.append(Reading(name: name, temp: temp))
}

// Drop sentinel readings from unpopulated sensors (e.g. PMU tdev* return ~-9200).
let valid = readings.filter { $0.temp > -100 && $0.temp < 200 }

// Collapse duplicates (same name reported by multiple services) → keep max per name.
var byName: [String: Double] = [:]
for r in valid { byName[r.name] = max(byName[r.name] ?? -Double.infinity, r.temp) }

print("Found \(readings.count) sensor readings, \(valid.count) valid, \(byName.count) unique:\n")
for (name, temp) in byName.sorted(by: { $0.key < $1.key }) {
    let padded = name.padding(toLength: 42, withPad: " ", startingAt: 0)
    print("  \(padded)\(String(format: "%6.2f", temp)) °C")
}

// On Apple Silicon, CPU and GPU share the die — max(PMU tdie*) is effectively max(CPU, GPU).
// PMU tcal is a calibrated package temp (separate from tdie); include it.
// On M1/M2 with explicit pACC/eACC/GPU sensors, those still match here.
let socTemps = byName.filter { name, _ in
    name.hasPrefix("PMU tdie") || name == "PMU tcal" ||
    name.hasPrefix("pACC") || name.hasPrefix("eACC") || name.hasPrefix("GPU")
}

let socMax = socTemps.values.max() ?? 0
print()
print(String(format: "SoC max (CPU/GPU die): %6.2f °C  (across %d sensors)", socMax, socTemps.count))
if let hottest = socTemps.max(by: { $0.value < $1.value }) {
    print("  hottest: \(hottest.key)")
}
#endif
