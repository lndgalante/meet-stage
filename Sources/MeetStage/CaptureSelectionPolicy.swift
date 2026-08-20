enum CaptureSelectionAction: Equatable {
    case pause
    case start
}

/// Keeps repeat selection behavior identical for clicks and global shortcuts.
enum CaptureSelectionPolicy {
    static func action<ID: Equatable>(
        for sourceID: ID,
        selectedWindowID: ID?,
        state: CaptureState
    ) -> CaptureSelectionAction {
        sourceID == selectedWindowID && state == .capturing ? .pause : .start
    }
}
