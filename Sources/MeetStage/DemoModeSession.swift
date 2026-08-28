import Foundation

/// High-frequency Demo Mode state that only the overlay and stage views observe,
/// kept off `CaptureManager` so transcription and highlight churn does not
/// invalidate the whole control and stage view tree.
///
/// The coordinator (`CaptureManager+DemoMode`) owns the speech, indexing, and
/// action pipeline and drives this session; the session owns only presentation
/// state and its dismissal timers.
@MainActor
final class DemoModeSession: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var caption: DemoCaption?
    @Published private(set) var highlights: [DemoHighlightPresentation] = []

    /// The current control index. Not published: it is read by the coordinator
    /// when resolving a command, never rendered.
    var elementIndex = DemoElementIndex.empty

    private var highlightDismissTasks: [UUID: Task<Void, Never>] = [:]
    private var captionRevertTask: Task<Void, Never>?

    deinit {
        highlightDismissTasks.values.forEach { $0.cancel() }
        captionRevertTask?.cancel()
    }

    func setListening(_ listening: Bool) {
        guard isListening != listening else { return }
        isListening = listening
        if listening {
            setCaption(.listening)
        } else {
            captionRevertTask?.cancel()
            captionRevertTask = nil
            caption = nil
        }
    }

    /// Sets the caption. Transient statuses revert to the listening pill after a
    /// short delay so the presenter always sees the mic is live.
    func setCaption(_ status: DemoCaptionStatus) {
        captionRevertTask?.cancel()
        captionRevertTask = nil
        caption = DemoCaption(status: status)

        guard status.isTransient, isListening else { return }
        captionRevertTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2.6))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, isListening else { return }
            caption = DemoCaption(status: .listening)
            captionRevertTask = nil
        }
    }

    func showHighlight(_ presentation: DemoHighlightPresentation) {
        highlights.append(presentation)
        highlightDismissTasks[presentation.id]?.cancel()
        highlightDismissTasks[presentation.id] = Task { [weak self] in
            do {
                try await Task.sleep(for: presentation.duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.dismissHighlight(presentation.id)
        }
    }

    private func dismissHighlight(_ id: UUID) {
        highlightDismissTasks[id]?.cancel()
        highlightDismissTasks[id] = nil
        highlights.removeAll { $0.id == id }
    }

    /// Immediately removes every highlight ring — used right after a click
    /// navigates, so a ring never lingers over a control that is now gone.
    func clearHighlights() {
        highlightDismissTasks.values.forEach { $0.cancel() }
        highlightDismissTasks.removeAll()
        highlights.removeAll()
    }

    /// Clears transient visuals (highlights and caption) without ending the
    /// session; used when focus is lost but Demo Mode remains armed.
    func clearVisuals() {
        highlightDismissTasks.values.forEach { $0.cancel() }
        highlightDismissTasks.removeAll()
        highlights.removeAll()
        captionRevertTask?.cancel()
        captionRevertTask = nil
        caption = isListening ? DemoCaption(status: .listening) : nil
    }

    /// Fully resets the session when Demo Mode stops or the source changes.
    func reset() {
        highlightDismissTasks.values.forEach { $0.cancel() }
        highlightDismissTasks.removeAll()
        captionRevertTask?.cancel()
        captionRevertTask = nil
        highlights.removeAll()
        caption = nil
        isListening = false
        elementIndex = .empty
    }
}
