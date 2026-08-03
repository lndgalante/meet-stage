import SwiftUI

@main
struct MeetStageApp: App {
    @StateObject private var captureManager = CaptureManager()

    var body: some Scene {
        Window("Meet Stage", id: "control") {
            ControlView(manager: captureManager)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 980, height: 720)

        Window("Meet Presenter Stage", id: "stage") {
            StageView(manager: captureManager)
                .frame(minWidth: 640, minHeight: 360)
        }
        .defaultSize(width: 1280, height: 720)

        .commands {
            CommandMenu("Capture") {
                Button("Refresh Windows") {
                    captureManager.refreshWindows()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Stop Capture") {
                    captureManager.stopCapture()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!captureManager.isCapturing)
            }
        }
    }
}
