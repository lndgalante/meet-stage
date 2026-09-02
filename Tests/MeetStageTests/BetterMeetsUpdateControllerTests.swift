import Foundation
import Testing
@testable import MeetStage

@Suite("Update configuration")
struct BetterMeetsUpdateControllerTests {
    @Test("Accepts only a complete HTTPS Sparkle configuration")
    func validatesConfiguration() {
        let configuration = BetterMeetsUpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://updates.example.com/appcast.xml",
                "SUPublicEDKey": "  public-key  "
            ]
        )

        #expect(configuration?.feedURL.absoluteString == "https://updates.example.com/appcast.xml")
        #expect(configuration?.publicKey == "public-key")
    }

    @Test("Rejects incomplete or insecure update metadata")
    func rejectsUnsafeConfiguration() {
        #expect(BetterMeetsUpdateConfiguration(infoDictionary: [:]) == nil)
        #expect(
            BetterMeetsUpdateConfiguration(
                infoDictionary: [
                    "SUFeedURL": "http://updates.example.com/appcast.xml",
                    "SUPublicEDKey": "public-key"
                ]
            ) == nil
        )
        #expect(
            BetterMeetsUpdateConfiguration(
                infoDictionary: [
                    "SUFeedURL": "https://updates.example.com/appcast.xml",
                    "SUPublicEDKey": "  "
                ]
            ) == nil
        )
    }
}
