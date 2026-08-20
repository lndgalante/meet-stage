import AppKit
import SwiftUI

@main
struct MeetStageApp: App {
    @StateObject private var captureManager = CaptureManager()

    init() {
        guard let iconURL = Bundle.main.url(forResource: "BetterDemos", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else { return }
        NSApplication.shared.applicationIconImage = icon
    }

    private var initialStageSize: NSSize {
        StageWindowSizing.defaultWindowContentSize()
    }

    var body: some Scene {
        Window("BetterDemos", id: "control") {
            ControlView(manager: captureManager)
                .frame(width: ControlWindowSizing.size.width, height: ControlWindowSizing.size.height)
        }
        .defaultSize(width: ControlWindowSizing.size.width, height: ControlWindowSizing.size.height)
        .windowResizability(.contentSize)

        Window("BetterDemos — Demo Stage", id: "stage") {
            StageView(manager: captureManager)
                .frame(minWidth: 480, minHeight: 270)
        }
        .defaultSize(width: initialStageSize.width, height: initialStageSize.height)
        .windowStyle(.hiddenTitleBar)

        .commands {
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
            }

            CommandMenu("Presentation") {
                Button("Toggle Annotations") {
                    captureManager.toggleAnnotations()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!captureManager.isLive)

                Button("Finish Annotating") {
                    captureManager.finishAnnotations()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!captureManager.isAnnotating)

                Button("Clear Annotations") {
                    captureManager.clearAnnotations()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(!captureManager.isLive)
            }
        }
    }
}
