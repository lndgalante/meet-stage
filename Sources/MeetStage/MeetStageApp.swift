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

    private var initialStageSize: NSSize {
        StageWindowSizing.defaultWindowContentSize()
    }

    var body: some Scene {
        Window("BetterMeets", id: "control") {
            ControlView(manager: captureManager)
                .frame(width: ControlWindowSizing.size.width, height: ControlWindowSizing.size.height)
        }
        .defaultSize(width: ControlWindowSizing.size.width, height: ControlWindowSizing.size.height)
        .windowResizability(.contentSize)
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
                Button("Refresh Windows") {
                    captureManager.refreshWindows()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(captureManager.isRefreshing)

                Button("Stop Capture") {
                    captureManager.stopCapture()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!captureManager.isCapturing)

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
                    captureManager.demoModeEnabled
                        ? "Turn Off Demo Mode"
                        : "Turn On Demo Mode"
                ) {
                    captureManager.toggleDemoMode()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Divider()

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

                Button("Finish Annotating") {
                    captureManager.finishAnnotations()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!captureManager.annotationsEnabled)

                Button("Clear Annotations") {
                    captureManager.clearAnnotations()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(captureManager.annotations.isEmpty)
            }

            CommandGroup(before: .windowList) {
                Button(windowState.controllerMenuTitle) {
                    BetterMeetsWindowActions.toggleController()
                }
                .keyboardShortcut("c", modifiers: [.command, .control])

                Button("Minimize Controller") {
                    BetterMeetsWindowActions.minimizeController()
                }
                .keyboardShortcut("m", modifiers: [.command, .control])
                .disabled(!windowState.controllerIsVisible)

                Button("Show Demo Stage") {
                    BetterMeetsWindowActions.showStage()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Minimize Demo Stage") {
                    BetterMeetsWindowActions.minimizeStage()
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(!windowState.stageCanMinimize)

                Button(windowState.stageFullScreenMenuTitle) {
                    BetterMeetsWindowActions.toggleStageFullScreen()
                }
                .keyboardShortcut("f", modifiers: [.command, .control, .option])

                Divider()
            }

            CommandGroup(replacing: .help) {
                Button("BetterMeets Help") {
                    BetterMeetsWindowActions.openHelp()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
        }

        Window("BetterMeets — Demo Stage", id: "stage") {
            StageView(manager: captureManager)
                .frame(minWidth: 480, minHeight: 270)
        }
        .defaultSize(width: initialStageSize.width, height: initialStageSize.height)
        .windowStyle(.hiddenTitleBar)

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
