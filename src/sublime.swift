import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

private let sublimeBundleIdentifier = "com.sublimetext.4"
private let setupTimeout: TimeInterval = 180

private func bundleIdentifier(at url: URL?) -> String? {
    guard let url else { return nil }
    return Bundle(url: url)?.bundleIdentifier
}

final class SetupDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var didFinish = false
    private var timeoutTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let workspace = NSWorkspace.shared
        guard let sublimeURL = workspace.urlForApplication(
            withBundleIdentifier: sublimeBundleIdentifier
        ) else {
            finish(code: 3, message: "omcli: Sublime Text is not installed")
            return
        }

        let currentURL = workspace.urlForApplication(toOpen: .plainText)
        if bundleIdentifier(at: currentURL) == sublimeBundleIdentifier {
            finish(code: 0, message: "Sublime Text already handles public.plain-text")
            return
        }

        showWindow()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: setupTimeout, repeats: false) {
            [weak self] _ in
            self?.finish(
                code: 4,
                message: "omcli: timed out waiting for macOS default-app consent"
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.didFinish else { return }
            workspace.setDefaultApplication(at: sublimeURL, toOpen: .plainText) {
                [weak self] error in
                DispatchQueue.main.async {
                    self?.handleCompletion(error: error, workspace: workspace)
                }
            }
        }
    }

    private func showWindow() {
        let frame = NSRect(x: 0, y: 0, width: 460, height: 150)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "omcli Sublime Setup"

        let label = NSTextField(
            wrappingLabelWithString:
                "Confirm the macOS request to use Sublime Text for plain-text files."
        )
        label.frame = NSRect(x: 36, y: 48, width: 388, height: 52)
        label.alignment = .center
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func handleCompletion(error: Error?, workspace: NSWorkspace) {
        let currentURL = workspace.urlForApplication(toOpen: .plainText)
        if bundleIdentifier(at: currentURL) == sublimeBundleIdentifier {
            finish(code: 0, message: "Configured Sublime Text for public.plain-text")
        } else if let error {
            finish(code: 3, message: "omcli: macOS rejected the default-app change: \(error)")
        } else {
            finish(
                code: 5,
                message: "omcli: macOS completed the request but the default app did not change"
            )
        }
    }

    private func finish(code: Int32, message: String) {
        guard !didFinish else { return }
        didFinish = true
        timeoutTimer?.invalidate()
        if code == 0 {
            print(message)
            fflush(stdout)
        } else {
            fputs("\(message)\n", stderr)
            fflush(stderr)
        }
        Darwin.exit(code)
    }
}

guard CommandLine.arguments.dropFirst().elementsEqual(["setup"]) else {
    fputs("omcli: internal Sublime helper expects setup\n", stderr)
    Darwin.exit(2)
}

let application = NSApplication.shared
let delegate = SetupDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
