import CoreGraphics
import Testing
@testable import MeetStage

@Suite("Shortcut assignment policy")
struct ShortcutAssignmentPolicyTests {
    @Test
    func testAutomaticAssignmentsFollowCandidateOrder() {
        let candidates = [
            candidate(id: 11, title: "Editor"),
            candidate(id: 22, title: "Browser"),
            candidate(id: 33, title: "Terminal")
        ]

        let resolution = resolve(candidates: candidates)

        #expect(resolution.assignments == [1: 11, 2: 22, 3: 33])
        #expect(resolution.pinnedAssignments.isEmpty)
    }

    @Test
    func testAutomaticAssignmentsRemainStableWhenCandidatesReorder() {
        let candidates = [
            candidate(id: 22, title: "Browser"),
            candidate(id: 11, title: "Editor"),
            candidate(id: 33, title: "Terminal")
        ]

        let resolution = resolve(
            candidates: candidates,
            previousAssignments: [1: 11, 2: 22]
        )

        #expect(resolution.assignments == [1: 11, 2: 22, 3: 33])
    }

    @Test
    func testUnavailablePinReservesItsSlot() {
        let missingPin = identity(title: "Missing")
        let available = candidate(id: 11, title: "Available")

        let resolution = resolve(candidates: [available], pins: [1: missingPin])

        #expect(resolution.assignments[1] == nil)
        #expect(resolution.assignments[2] == available.id)
    }

    @Test
    func testAmbiguousPinDoesNotGuess() {
        let pin = identity(title: "Document")
        let candidates = [
            ShortcutCandidate(id: 11, identity: pin),
            ShortcutCandidate(id: 22, identity: pin)
        ]

        let resolution = resolve(candidates: candidates, pins: [3: pin])

        #expect(resolution.assignments[3] == nil)
        #expect(resolution.pinnedAssignments.isEmpty)
        #expect(Set(resolution.assignments.values) == [11, 22])
    }

    @Test
    func testResolvedPinTracksAWindowWhoseTitleChanges() {
        let oldIdentity = identity(title: "Draft")
        let renamedIdentity = identity(title: "Final")
        let renamedCandidate = ShortcutCandidate(id: 42, identity: renamedIdentity)

        let resolution = resolve(
            candidates: [renamedCandidate],
            pins: [4: oldIdentity],
            previousPinnedAssignments: [4: 42]
        )

        #expect(resolution.assignments[4] == 42)
        #expect(resolution.pinnedAssignments[4] == 42)
        #expect(resolution.pins[4] == renamedIdentity)
    }

    @Test
    func testExcludedWindowIsNeitherPreservedNorReassigned() {
        let excludedCandidate = candidate(id: 11, title: "Excluded")
        let availableCandidate = candidate(id: 22, title: "Available")

        let resolution = resolve(
            candidates: [excludedCandidate, availableCandidate],
            exclusions: [excludedCandidate.identity],
            previousAssignments: [1: excludedCandidate.id]
        )

        #expect(resolution.assignments == [1: availableCandidate.id])
    }

    @Test
    func testDuplicateCandidateIDsAreAssignedOnlyOnce() {
        let duplicate = candidate(id: 11, title: "Editor")

        let resolution = resolve(candidates: [duplicate, duplicate])

        #expect(resolution.assignments == [1: duplicate.id])
    }

    @Test
    func testWindowIdentityUsesBundleIdentifierWhenAvailable() {
        let saved = identity(application: "Old Name", title: "Editor", bundleIdentifier: "dev.example.app")
        let renamedApp = identity(application: "New Name", title: "Editor", bundleIdentifier: "dev.example.app")
        let differentApp = identity(application: "Old Name", title: "Editor", bundleIdentifier: "dev.example.other")

        #expect(saved.matches(renamedApp))
        #expect(!saved.matches(differentApp))
    }

    @Test
    func testWindowIdentityFallsBackToApplicationNameWithoutBundleIdentifier() {
        let saved = identity(application: "Utility", title: "Panel", bundleIdentifier: "")
        let sameApplication = identity(application: "Utility", title: "Panel", bundleIdentifier: "dev.example.utility")
        let differentApplication = identity(application: "Other", title: "Panel", bundleIdentifier: "")

        #expect(saved.matches(sameApplication))
        #expect(!saved.matches(differentApplication))
    }

    private func resolve(
        candidates: [ShortcutCandidate],
        pins: [Int: PinnedWindow] = [:],
        exclusions: Set<PinnedWindow> = [],
        previousAssignments: [Int: CGWindowID] = [:],
        previousPinnedAssignments: [Int: CGWindowID] = [:]
    ) -> ShortcutResolution {
        ShortcutAssignmentPolicy.resolve(
            candidates: candidates,
            pins: pins,
            exclusions: exclusions,
            previousAssignments: previousAssignments,
            previousPinnedAssignments: previousPinnedAssignments
        )
    }

    private func candidate(id: CGWindowID, title: String) -> ShortcutCandidate {
        ShortcutCandidate(id: id, identity: identity(title: title))
    }

    private func identity(
        application: String = "Example",
        title: String,
        bundleIdentifier: String = "dev.example.app"
    ) -> PinnedWindow {
        PinnedWindow(
            bundleIdentifier: bundleIdentifier,
            applicationName: application,
            title: title
        )
    }
}
