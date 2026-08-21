import CoreGraphics
import Testing
@testable import MeetStage

@Suite("Window discovery policy")
struct WindowDiscoveryPolicyTests {
    @Test("Accepts a titled app window at the minimum supported size")
    func acceptsEligibleWindow() {
        let candidate = Self.makeCandidate(
            frame: CGRect(origin: .zero, size: WindowDiscoveryPolicy.minimumSize)
        )

        #expect(
            WindowDiscoveryPolicy.isEligible(
                candidate,
                excludingBundleIdentifier: "dev.bettermeets"
            )
        )
    }

    @Test(
        "Rejects windows that do not belong in the picker",
        arguments: [
            makeCandidate(layer: 1),
            makeCandidate(frame: CGRect(x: 0, y: 0, width: 159, height: 100)),
            makeCandidate(frame: CGRect(x: 0, y: 0, width: 160, height: 99)),
            makeCandidate(title: "  \n"),
            makeCandidate(hasOwningApplication: false),
            makeCandidate(bundleIdentifier: "dev.bettermeets")
        ]
    )
    func rejectsIneligibleWindow(_ candidate: WindowDiscoveryCandidate) {
        #expect(
            !WindowDiscoveryPolicy.isEligible(
                candidate,
                excludingBundleIdentifier: "dev.bettermeets"
            )
        )
    }

    @Test("Does not exclude an app when the current bundle identifier is unavailable")
    func handlesMissingOwnBundleIdentifier() {
        #expect(
            WindowDiscoveryPolicy.isEligible(
                Self.makeCandidate(bundleIdentifier: nil),
                excludingBundleIdentifier: nil
            )
        )
    }

    private static func makeCandidate(
        layer: Int = 0,
        frame: CGRect = CGRect(x: 0, y: 0, width: 640, height: 360),
        title: String? = "Document",
        hasOwningApplication: Bool = true,
        bundleIdentifier: String? = "dev.example.app"
    ) -> WindowDiscoveryCandidate {
        WindowDiscoveryCandidate(
            layer: layer,
            frame: frame,
            title: title,
            hasOwningApplication: hasOwningApplication,
            bundleIdentifier: bundleIdentifier
        )
    }
}
