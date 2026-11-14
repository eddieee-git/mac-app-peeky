import AppKit

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run() ? 0 : 1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
