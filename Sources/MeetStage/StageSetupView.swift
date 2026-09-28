import SwiftUI

struct StageSetupView: View {
    @ObservedObject var manager: CaptureManager

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.padding(32)
            ScrollView { content.padding(24) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 18) {
            if manager.state == .switching || manager.state == .loading {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(manager.state == .paused ? Color.orange : .secondary)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                Text(title).font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
            if manager.state == .idle && !manager.windows.isEmpty {
                SharingSteps().padding(.top, 8)
            }
        }
        .frame(maxWidth: 410)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var actions: some View {
        switch manager.state {
        case .paused:
            if manager.canToggleCapturePause {
                Button("Resume Stage", systemImage: "play.fill", action: manager.toggleCapturePause)
                    .buttonStyle(.borderedProminent)
            }
        case .permissionRequired:
            if manager.requestedPermissionThisLaunch {
                Button("Open System Settings", action: manager.openScreenRecordingSettings)
                    .buttonStyle(.borderedProminent)
                Text("Already enabled access? Restart BetterMeets to try again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Restart BetterMeets", action: manager.restartApplication)
                    .buttonStyle(.link)
            } else {
                Button("Allow Screen Recording", action: manager.requestScreenRecordingPermission)
                    .buttonStyle(.borderedProminent)
                Button("Open System Settings", action: manager.openScreenRecordingSettings)
                    .buttonStyle(.link)
            }
        case .failed:
            HStack {
                if let source = manager.selectedSource {
                    Button("Try Again") { manager.select(source) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Refresh Windows", action: manager.refreshWindows)
                        .buttonStyle(.borderedProminent)
                }
            }
        case .idle:
            if manager.windows.isEmpty {
                Button("Refresh Windows", action: manager.refreshWindows)
            }
        case .switching:
            Button("Cancel", action: manager.stopCapture)
        default:
            EmptyView()
        }
    }

    private var title: String {
        switch manager.state {
        case .paused: "Stage paused"
        case .permissionRequired: "Screen recording access needed"
        case .failed: "Window unavailable"
        case .switching: "Preparing your window"
        case .loading: "Finding windows"
        default: manager.windows.isEmpty ? "Open a window to get started" : "Choose a window to present"
        }
    }

    private var detail: String {
        switch manager.state {
        case .paused:
            manager.selectedSource.map { "\($0.applicationName) is hidden. Resume when you’re ready." }
                ?? "The source window has closed. Choose another window to continue."
        case .permissionRequired:
            "Allow BetterMeets to capture the windows you choose."
        case .failed:
            "Restore the source window and try again, or choose another window."
        case .switching:
            "The stage will appear when the window is ready."
        case .loading:
            "Looking for available app windows."
        default:
            manager.windows.isEmpty
                ? "Open an app window, then refresh the list."
                : "Keep one shared window as you switch between apps."
        }
    }

    private var symbol: String {
        switch manager.state {
        case .paused: "pause.circle"
        case .permissionRequired: "lock.rectangle"
        case .failed: "exclamationmark.triangle"
        default: "rectangle.on.rectangle"
        }
    }
}
