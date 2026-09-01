import AppKit
import SwiftUI
import Testing
@testable import MeetStage

@Suite("Spotlight effect")
struct SpotlightEffectTests {
    @Test("Only shows the spotlight for an actively captured selected window")
    func gatesSpotlightVisibility() {
        #expect(
            SpotlightVisibilityPolicy.shouldShow(
                isEnabled: true,
                captureState: .capturing,
                hasActiveCapture: true,
                hasSelectedWindow: true
            )
        )

        for state: CaptureState in [
            .idle,
            .loading,
            .switching,
            .paused,
            .permissionRequired,
            .failed("Unavailable")
        ] {
            #expect(
                !SpotlightVisibilityPolicy.shouldShow(
                    isEnabled: true,
                    captureState: state,
                    hasActiveCapture: true,
                    hasSelectedWindow: true
                )
            )
        }

        #expect(
            !SpotlightVisibilityPolicy.shouldShow(
                isEnabled: true,
                captureState: .capturing,
                hasActiveCapture: false,
                hasSelectedWindow: true
            )
        )
        #expect(
            !SpotlightVisibilityPolicy.shouldShow(
                isEnabled: true,
                captureState: .capturing,
                hasActiveCapture: true,
                hasSelectedWindow: false
            )
        )
        #expect(
            !SpotlightVisibilityPolicy.shouldShow(
                isEnabled: false,
                captureState: .capturing,
                hasActiveCapture: true,
                hasSelectedWindow: true
            )
        )
    }

    @Test("Maps the global pointer into the selected window")
    func normalizesPointerLocation() {
        let location = WindowCoordinateGeometry.normalizedPoint(
            inside: CGPoint(x: 250, y: 250),
            sourceFrame: CGRect(x: 100, y: 200, width: 300, height: 200)
        )

        #expect(location == NormalizedWindowPoint(x: 0.5, y: 0.25))
    }

    @Test("Rejects pointer movement outside the selected window")
    func rejectsOutOfBoundsPointer() {
        let location = WindowCoordinateGeometry.normalizedPoint(
            inside: CGPoint(x: 401, y: 250),
            sourceFrame: CGRect(x: 100, y: 200, width: 300, height: 200)
        )

        #expect(location == nil)
    }

    @Test("Keeps the aperture useful across window sizes")
    func sizesApertureResponsively() {
        #expect(
            SpotlightGeometry.apertureDiameter(
                in: CGSize(width: 640, height: 360)
            ) == 151.2
        )
        #expect(
            SpotlightGeometry.apertureDiameter(
                in: CGSize(width: 1_440, height: 900)
            ) == 360
        )
        #expect(
            SpotlightGeometry.apertureDiameter(
                in: CGSize(width: 120, height: 100)
            ) == 82
        )
    }

    @Test("Offers distinct useful spotlight sizes")
    func supportsSpotlightSizes() {
        let viewport = CGSize(width: 1_440, height: 900)

        let small = SpotlightGeometry.apertureDiameter(in: viewport, size: .small)
        let medium = SpotlightGeometry.apertureDiameter(in: viewport, size: .medium)
        let large = SpotlightGeometry.apertureDiameter(in: viewport, size: .large)

        #expect(small == 280)
        #expect(medium == 360)
        #expect(large == 480)
        #expect(small < medium)
        #expect(medium < large)
    }

    @Test("Lets the aperture center reach a window corner")
    func targetsWindowCorners() {
        let aperture = SpotlightGeometry.apertureRect(
            at: NormalizedWindowPoint(x: 0, y: 1),
            in: CGSize(width: 640, height: 360)
        )

        #expect(aperture.midX == 0)
        #expect(aperture.midY == 360)
        #expect(aperture.minX < 0)
        #expect(aperture.maxY > 360)
    }

    @Test("Clamps programmatic spotlight movement")
    @MainActor
    func clampsSessionLocation() {
        let session = SpotlightSession()

        session.move(to: NormalizedWindowPoint(x: -0.2, y: 1.4))

        #expect(session.location == NormalizedWindowPoint(x: 0, y: 1))
    }

    @Test("Updates and normalizes the live spotlight appearance")
    @MainActor
    func updatesSessionAppearance() {
        let session = SpotlightSession()

        session.setSize(.large)
        session.setOutsideOpacity(4)

        #expect(session.size == .large)
        #expect(session.outsideOpacity == SpotlightAppearance.outsideOpacityRange.upperBound)
    }

    @Test("Non-finite spotlight state returns to safe defaults")
    @MainActor
    func rejectsNonFiniteSpotlightState() {
        let session = SpotlightSession()

        session.move(to: NormalizedWindowPoint(x: .nan, y: .infinity))
        session.setOutsideOpacity(.nan)

        #expect(session.location == NormalizedWindowPoint(x: 0.5, y: 0.5))
        #expect(session.outsideOpacity == SpotlightAppearance.defaultOutsideOpacity)
    }

    @Test("Observes pointer movement delivered inside BetterMeets")
    @MainActor
    func observesLocalPointerMovement() {
        let monitor = GlobalPointerMonitor(pointerMovements: { _ in })

        monitor.start()
        #expect(monitor.observesLocalApplicationEvents)

        monitor.stop()
        #expect(!monitor.observesLocalApplicationEvents)
    }

    @Test("Arms the spotlight without a live source")
    @MainActor
    func armsSpotlightWhileIdle() throws {
        let suiteName = "SpotlightArmingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = CaptureManager(defaults: defaults)

        manager.toggleSpotlight()

        #expect(manager.spotlightEnabled)

        manager.toggleSpotlight()

        #expect(!manager.spotlightEnabled)
    }

    @Test("The source spotlight is click-through and below source ink")
    @MainActor
    func configuresSourceSpotlightWindow() {
        let panel = SpotlightPanel(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        SpotlightWindowPolicy.configure(panel)
        panel.orderFrontRegardless()
        defer { panel.close() }

        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(SpotlightWindowPolicy.sourceOverlayLevel.rawValue > NSWindow.Level.normal.rawValue)
        #expect(
            SpotlightWindowPolicy.sourceOverlayLevel.rawValue
                < AnnotationWindowPolicy.sourceOverlayLevel.rawValue
        )
    }
}
