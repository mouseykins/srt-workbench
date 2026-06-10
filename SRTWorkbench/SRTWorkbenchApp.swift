import SwiftUI

@main
struct SRTWorkbenchApp: App {
    init() {
        log(.app, "=== SRT Workbench \(DiagnosticsService.appVersion()) launched — macOS \(ProcessInfo.processInfo.operatingSystemVersionString) ===")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // File > Save SRT (⌘S) — routed by notification so the command
            // works without the scene holding a view-model reference.
            CommandGroup(replacing: .saveItem) {
                Button("Save SRT") {
                    NotificationCenter.default.post(name: .saveSRTRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandMenu("Playback") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .togglePlayback, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Back 5 Seconds") {
                    NotificationCenter.default.post(name: .skipBackward, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Forward 5 Seconds") {
                    NotificationCenter.default.post(name: .skipForward, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Divider()

                Button("Toggle Speed 1x / 2x") {
                    NotificationCenter.default.post(name: .togglePlaybackSpeedRequested, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
            }

            CommandGroup(after: .help) {
                Divider()
                Button("Open Log Folder") {
                    DiagnosticsService.openLogFolder()
                }
                Button("Copy Diagnostics") {
                    Task { await DiagnosticsService.copyReportToClipboard() }
                }
            }
        }
    }
}
