import AppKit
import SwiftUI

@main
struct MeetStageApp: App {
    @NSApplicationDelegateAdaptor(BetterMeetsAppDelegate.self) private var appDelegate
    @StateObject private var captureManager = CaptureManager.shared
    @StateObject private var windowState = BetterMeetsWindowState.shared
    @StateObject private var updateController = BetterMeetsUpdateController()

    init() {
        guard let iconURL = Bundle.main.url(forResource: "BetterMeets", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else { return }
        NSApplication.shared.applicationIconImage = icon
    }

    var body: some Scene {
        Window("BetterMeets", id: "workspace") {
            WorkspaceView(manager: captureManager)
        }
        .defaultSize(width: WorkspaceMetrics.defaultSize.width, height: WorkspaceMetrics.defaultSize.height)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.isConfigured)
            }

            CommandGroup(replacing: .undoRedo) {
                Button(captureManager.annotationUndoManager.undoMenuItemTitle) {
                    captureManager.annotationUndoManager.undo()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!captureManager.annotationUndoManager.canUndo)

                Button(captureManager.annotationUndoManager.redoMenuItemTitle) {
                    captureManager.annotationUndoManager.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!captureManager.annotationUndoManager.canRedo)
            }

            CommandMenu("Capture") {
                Button(captureManager.state == .paused ? "Resume Sharing" : "Pause Sharing") {
                    captureManager.toggleCapturePause()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!captureManager.canToggleCapturePause)

                Button("Open Source App") {
                    captureManager.focusSelectedSourceIfPossible()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!captureManager.isLive)
                Divider()

                Button("Refresh Windows") {
                    captureManager.refreshWindows()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(captureManager.isRefreshing)

                Button("Stop Capture") {
                    captureManager.stopCapture()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!captureManager.canStopCapture)

                Divider()

                Menu("Source Slots") {
                    ForEach(Array(ShortcutSlot.all), id: \.self) { slot in
                        if let modifiers = captureManager.globalShortcutModifier.eventModifiers {
                            sourceSlotButton(slot)
                                .keyboardShortcut(
                                    KeyEquivalent(Character(String(slot))),
                                    modifiers: modifiers
                                )
                        } else {
                            sourceSlotButton(slot)
                        }
                    }
                }
            }

            CommandMenu("Presentation") {
                Button(
                    captureManager.autoPresentationEnabled
                        ? "Turn Off Auto Polish"
                        : "Turn On Auto Polish"
                ) {
                    captureManager.toggleAutoPresentation()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button(captureManager.spotlightEnabled ? "Turn Off Spotlight" : "Turn On Spotlight") {
                    captureManager.toggleSpotlight()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button(captureManager.annotationsEnabled ? "Turn Off Annotations" : "Turn On Annotations") {
                    captureManager.toggleAnnotations()
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Button(
                    captureManager.highlightsMouseClicks
                        ? "Turn Off Click Highlighting"
                        : "Turn On Click Highlighting"
                ) {
                    captureManager.toggleMouseClickHighlighting()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button(
                    captureManager.highlightsKeystrokes
                        ? "Turn Off Keystroke Highlighting"
                        : "Turn On Keystroke Highlighting"
                ) {
                    captureManager.toggleKeystrokeHighlighting()
                }
                .keyboardShortcut("k", modifiers: [.command, .option])

                Button(captureManager.annotationsEnabled ? "Finish Annotating" : "Show Controls") {
                    if captureManager.annotationsEnabled {
                        captureManager.finishAnnotations()
                    } else {
                        windowState.stageOnly = false
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!captureManager.annotationsEnabled && !windowState.stageOnly)

                Button("Clear Annotations") {
                    captureManager.clearAnnotations()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(captureManager.annotations.isEmpty)
            }

            CommandGroup(before: .sidebar) {
                Button(windowState.stageOnly ? "Show Controls" : "Stage Only") {
                    windowState.toggleStageOnly()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            CommandGroup(before: .windowList) {
                Button("Show BetterMeets") {
                    BetterMeetsWindowActions.showStage()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Show Source Tools") {
                    BetterMeetsWindowActions.showStageActions()
                }
                .keyboardShortcut("t", modifiers: [.command, .control])
                .disabled(captureManager.selectedSource == nil)
                Divider()
            }

            CommandGroup(replacing: .help) {
                Button("BetterMeets Help") {
                    BetterMeetsWindowActions.openHelp()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
        }

        Settings {
            BetterMeetsSettingsView(manager: captureManager)
        }
    }

    private func sourceSlotButton(_ slot: Int) -> some View {
        Button(sourceSlotTitle(slot)) {
            captureManager.activateShortcut(slot)
        }
        .disabled(
            captureManager.window(forShortcutSlot: slot) == nil
                || captureManager.unavailableShortcutSlots.contains(slot)
        )
    }

    private func sourceSlotTitle(_ slot: Int) -> String {
        guard let source = captureManager.window(forShortcutSlot: slot) else {
            if let owner = captureManager.shortcutOwnerDescription(for: slot) {
                return "Slot \(slot) — \(owner) Unavailable"
            }
            return "Slot \(slot) — Empty"
        }

        let prefix: String
        if source.id == captureManager.selectedWindowID {
            prefix = captureManager.state == .paused ? "Resume" : "Pause"
        } else {
            prefix = "Share"
        }
        return "\(prefix) \(source.applicationName) — \(source.title)"
    }
}
