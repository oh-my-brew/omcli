import Darwin
import Foundation

private let frameworkPath = "/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore"
private let operationTimeout: DispatchTimeInterval = .seconds(30)

private enum ExitCode: Int32 {
    case invalidInput = 1
    case noDevices = 2
    case selectionRequired = 3
    case sidecarError = 4
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data("omcli sidecar: \(message)\n".utf8))
}

private func fail(_ message: String, code: ExitCode) -> Never {
    writeError(message)
    exit(code.rawValue)
}

private func deviceName(_ device: NSObject) -> String {
    let selector = Selector(("name"))
    guard device.responds(to: selector),
          let value = device.perform(selector)?.takeUnretainedValue() as? String else {
        fail("Sidecar returned a device without a name", code: .sidecarError)
    }
    return value
}

private func deviceNames(_ devices: [NSObject]) -> [String] {
    devices.map(deviceName).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

private func printDevices(_ devices: [NSObject], heading: String? = nil) {
    if let heading {
        writeError(heading)
    }
    for name in deviceNames(devices) {
        writeError("  \(name)")
    }
}

private func managerDevices(_ manager: NSObject, selectorName: String) -> [NSObject] {
    let selector = Selector((selectorName))
    guard manager.responds(to: selector),
          let devices = manager.perform(selector)?.takeUnretainedValue() as? [NSObject] else {
        fail("the current macOS Sidecar framework does not provide \(selectorName)", code: .sidecarError)
    }
    return devices
}

private func selectDevice(
    from devices: [NSObject],
    requestedName: String?,
    emptyMessage: String,
    ambiguousMessage: String,
    emptyIsSuccess: Bool
) -> NSObject? {
    if let requestedName {
        guard let match = devices.first(where: {
            deviceName($0).caseInsensitiveCompare(requestedName) == .orderedSame
        }) else {
            if !devices.isEmpty {
                printDevices(devices, heading: "available devices:")
            }
            fail("device is not available: \(requestedName)", code: .selectionRequired)
        }
        return match
    }

    switch devices.count {
    case 0:
        if emptyIsSuccess {
            print(emptyMessage)
            return nil
        }
        fail(emptyMessage, code: .noDevices)
    case 1:
        return devices[0]
    default:
        printDevices(devices, heading: ambiguousMessage)
        fail("specify a device name", code: .selectionRequired)
    }
}

private func runOperation(manager: NSObject, selectorName: String, device: NSObject) {
    let selector = Selector((selectorName))
    guard manager.responds(to: selector) else {
        fail("the current macOS Sidecar framework does not support this operation", code: .sidecarError)
    }

    let group = DispatchGroup()
    var operationError: NSError?
    let completion: @convention(block) (NSError?) -> Void = { error in
        operationError = error
        group.leave()
    }

    group.enter()
    _ = manager.perform(selector, with: device, with: completion)
    if group.wait(timeout: .now() + operationTimeout) == .timedOut {
        fail("operation timed out", code: .sidecarError)
    }
    if let operationError {
        fail(operationError.localizedDescription, code: .sidecarError)
    }
}

private func printUsage() {
    print("""
    Usage: omcli sidecar <command> [device]

    Commands:
      list                   List reachable Sidecar devices
      connect [DEVICE]       Connect DEVICE, or the only reachable device
      disconnect [DEVICE]    Disconnect DEVICE, or the only connected device
      help                   Show this help
    """)
}

guard dlopen(frameworkPath, RTLD_LAZY) != nil else {
    fail("SidecarCore is unavailable on this Mac", code: .sidecarError)
}
guard let managerClass = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
      let manager = managerClass.perform(Selector(("sharedManager")))?.takeUnretainedValue() as? NSObject else {
    fail("SidecarDisplayManager is unavailable on this macOS version", code: .sidecarError)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    printUsage()
    exit(ExitCode.invalidInput.rawValue)
}

switch command {
case "help", "-h", "--help":
    guard arguments.count == 1 else {
        fail("help does not accept arguments", code: .invalidInput)
    }
    printUsage()

case "list":
    guard arguments.count == 1 else {
        fail("list does not accept arguments", code: .invalidInput)
    }
    let devices = managerDevices(manager, selectorName: "devices")
    guard !devices.isEmpty else {
        fail("no reachable Sidecar devices found", code: .noDevices)
    }
    for name in deviceNames(devices) {
        print(name)
    }

case "connect":
    guard arguments.count <= 2 else {
        fail("connect accepts at most one device name", code: .invalidInput)
    }
    let requestedName = arguments.count == 2 ? arguments[1] : nil
    let reachable = managerDevices(manager, selectorName: "devices")
    guard let device = selectDevice(
        from: reachable,
        requestedName: requestedName,
        emptyMessage: "no reachable Sidecar devices found",
        ambiguousMessage: "multiple reachable Sidecar devices found:",
        emptyIsSuccess: false
    ) else {
        exit(ExitCode.noDevices.rawValue)
    }

    let connected = managerDevices(manager, selectorName: "connectedDevices")
    let name = deviceName(device)
    if connected.contains(where: { deviceName($0).caseInsensitiveCompare(name) == .orderedSame }) {
        print("already connected: \(name)")
        exit(0)
    }
    runOperation(manager: manager, selectorName: "connectToDevice:completion:", device: device)
    print("connected: \(name)")

case "disconnect":
    guard arguments.count <= 2 else {
        fail("disconnect accepts at most one device name", code: .invalidInput)
    }
    let requestedName = arguments.count == 2 ? arguments[1] : nil
    let connected = managerDevices(manager, selectorName: "connectedDevices")
    guard let device = selectDevice(
        from: connected,
        requestedName: requestedName,
        emptyMessage: "no Sidecar devices are connected",
        ambiguousMessage: "multiple Sidecar devices are connected:",
        emptyIsSuccess: requestedName == nil
    ) else {
        exit(0)
    }

    let name = deviceName(device)
    runOperation(manager: manager, selectorName: "disconnectFromDevice:completion:", device: device)
    print("disconnected: \(name)")

default:
    fail("unknown command: \(command)", code: .invalidInput)
}
