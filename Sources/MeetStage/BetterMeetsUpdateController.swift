import Foundation
import Sparkle

struct BetterMeetsUpdateConfiguration: Equatable {
    let feedURL: URL
    let publicKey: String

    init?(infoDictionary: [String: Any]) {
        guard
            let feedValue = infoDictionary["SUFeedURL"] as? String,
            let feedURL = URL(string: feedValue),
            feedURL.scheme?.lowercased() == "https",
            feedURL.host != nil,
            let keyValue = infoDictionary["SUPublicEDKey"] as? String
        else { return nil }

        let publicKey = keyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicKey.isEmpty else { return nil }
        self.feedURL = feedURL
        self.publicKey = publicKey
    }
}

/// Owns Sparkle's standard updater for the lifetime of the SwiftUI application.
/// Local builds without release feed credentials remain intentionally inert.
@MainActor
final class BetterMeetsUpdateController: ObservableObject {
    let isConfigured: Bool
    private let updaterController: SPUStandardUpdaterController?

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        let configuration = BetterMeetsUpdateConfiguration(
            infoDictionary: infoDictionary
        )
        isConfigured = configuration != nil
        updaterController = configuration.map { _ in
            SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
