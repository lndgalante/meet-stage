import SwiftUI

struct ControlView: View {
    @ObservedObject var manager: CaptureManager
    @Environment(\.openWindow) private var openWindow

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                if manager.windows.isEmpty {
                    emptyState
                } else {
                    windowGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .background(WindowConfigurator(kind: .control))
        .task {
            openWindow(id: "stage")
            manager.refreshWindows()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meet Stage")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Choose what appears in the window shared with Google Meet.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StateBadge(state: manager.state)
            }

            HStack(spacing: 10) {
                Button {
                    manager.refreshWindows()
                } label: {
                    Label("Refresh Windows", systemImage: "arrow.clockwise")
                }
                .disabled(manager.state == .loading)

                Button {
                    openWindow(id: "stage")
                } label: {
                    Label("Show Presenter Stage", systemImage: "rectangle.on.rectangle")
                }

                if manager.isCapturing {
                    Button(role: .destructive) {
                        manager.stopCapture()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
            }
        }
        .padding(20)
    }

    private var windowGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(manager.windows) { source in
                    WindowCard(
                        source: source,
                        isSelected: source.id == manager.selectedWindowID
                    ) {
                        manager.select(source)
                    }
                }
            }
            .padding(20)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                manager.state == .loading ? "Finding Windows" : "No Windows Available",
                systemImage: manager.state == .loading ? "rectangle.stack.badge.clock" : "rectangle.slash"
            )
        } description: {
            if let message = manager.errorMessage {
                Text(message)
            } else if manager.state == .loading {
                Text("macOS may ask for Screen Recording permission.")
            } else {
                Text("Open another application, then refresh the list.")
            }
        } actions: {
            if manager.errorMessage != nil {
                Button("Open Screen Recording Settings") {
                    manager.openScreenRecordingSettings()
                }
                Button("Try Again") {
                    manager.refreshWindows()
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: manager.isCapturing ? "dot.radiowaves.left.and.right" : "circle.dashed")
                .foregroundStyle(manager.isCapturing ? .green : .secondary)
            Text(manager.selectedWindowDescription)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("In Meet, share “Meet Presenter Stage” once.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .frame(height: 48)
    }
}

private struct WindowCard: View {
    let source: WindowSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Color.black

                    if let thumbnail = source.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                    } else if let icon = source.applicationIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 38))
                            .foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .blue)
                            .font(.title2)
                            .padding(8)
                    }
                }

                HStack(spacing: 8) {
                    if let icon = source.applicationIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(source.applicationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share \(source.applicationName), \(source.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct StateBadge: View {
    let state: CaptureState

    private var color: Color {
        switch state {
        case .capturing:
            return .green
        case .failed:
            return .red
        case .loading, .switching:
            return .orange
        case .idle:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(state.label)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    enum Kind {
        case control
        case stage
    }

    let kind: Kind

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        switch kind {
        case .control:
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
        case .stage:
            window.aspectRatio = NSSize(width: 16, height: 9)
            window.collectionBehavior.insert(.canJoinAllSpaces)
        }
    }
}
