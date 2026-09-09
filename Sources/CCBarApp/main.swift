import AppKit

// Top-level code in main.swift isn't implicitly @MainActor-isolated, but
// app launch always happens on the main thread — assumeIsolated documents
// that guarantee to the compiler.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    app.run()
}
