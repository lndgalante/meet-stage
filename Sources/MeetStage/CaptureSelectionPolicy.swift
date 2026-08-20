enum CaptureSelectionAction: Equatable {
    case pause
    case start
}

enum UnavailableSelectionRecoveryAction<ID: Equatable>: Equatable {
    case restore(ID)
    case fail
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

/// Decides whether a failed source switch can safely return to the source that
/// was live before it. A reselected source cannot be its own fallback.
enum UnavailableSelectionRecoveryPolicy {
    static func action<ID: Equatable>(
        failedSourceID: ID,
        selectedWindowID: ID?,
        availableWindowIDs: [ID]
    ) -> UnavailableSelectionRecoveryAction<ID> {
        guard let selectedWindowID,
            selectedWindowID != failedSourceID,
            availableWindowIDs.contains(selectedWindowID)
        else {
            return .fail
        }
        return .restore(selectedWindowID)
    }
}
