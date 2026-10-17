import CoreGraphics
import Foundation

/// Geometry for showing a demo target whole before it's highlighted or acted on:
/// whether the edge of its page or list cuts it, which scroll brings it in, how
/// far the content really moved, and where its highlight may be drawn.
///
/// Chromium reports frames clipped to the viewport: a section running past the
/// fold ends exactly at the fold, and one wholly past it is a one-point strip
/// there. So a frame touching the viewport's edge counts as cut, and only edges
/// away from it are trusted when measuring a scroll.
enum DemoFraming {
    enum Purpose: Sendable {
        /// A highlight: the whole target, or a tall target's top, comfortably in view.
        case highlight
        /// A click or typing: only a target the edge cuts, and only with a background scroll.
        case action
    }

    /// One scroll toward a framed target.
    enum Move: Equatable, Sendable {
        /// `AXScrollToVisible` on a node, which works with the app in the background.
        case reveal(Int)
        /// An exact scroll in window fractions; positive moves the content up.
        case scroll(Double)
    }

    /// What earlier moves for the same target tried and did.
    struct Progress: Sendable {
        var revealed = false
        var revealedTop = false
        var revealMoved = false
        var scrolled = false
        /// Taller than the viewport, so its top is shown instead of all of it.
        var tall = false
        /// The edges that cut the targets when they were first scrolled into view.
        var firstCutTop = false
        var firstCutBottom = false
    }

    /// Room kept between a framed target and the viewport's edge, in points.
    static let margin = 24.0
    /// How close to an edge, in points, a frame counts as touching it.
    static let edgeTolerance = 1.5

    // MARK: Planning

    /// The viewport that cuts these nodes, when they all sit in the same scrolling
    /// content. Nil otherwise: a native control, a browser's toolbar next to the
    /// page, or targets in two panes are never scrolled for and never clamped.
    static func viewport(of nodes: [AXNode]) -> NormRect? {
        let viewports = nodes.compactMap(\.viewport)
        guard let first = viewports.first, viewports.count == nodes.count,
            viewports.allSatisfy({ $0.isClose(to: first) })
        else { return nil }
        return first
    }

    static func union(of nodes: [AXNode]) -> NormRect? {
        guard let first = nodes.first?.rect else { return nil }
        return nodes.dropFirst().reduce(first) { $0.union($1.rect) }
    }

    /// The next scroll toward showing `nodes` whole, or nil once they're framed or
    /// nothing more would help. A target the viewport doesn't cut never scrolls.
    static func nextMove(
        for nodes: [AXNode], in snapshot: AXSnapshot, purpose: Purpose, progress: inout Progress
    ) -> Move? {
        guard let viewport = viewport(of: nodes), let target = union(of: nodes) else { return nil }
        let unit = 1 / max(snapshot.windowFrame.height, 1)
        let edge = edgeTolerance * unit
        let margin = margin * unit
        let cutTop = target.y < viewport.y + edge
        let cutBottom = target.maxY > viewport.maxY - edge
        guard cutTop || cutBottom else { return nil }
        if (cutTop && cutBottom) || target.h > viewport.h - 2 * margin { progress.tall = true }
        let topmost = nodes.min { $0.rect.y < $1.rect.y }
        // Scrolling the node on the cut side into view: Chromium and Gecko center it,
        // WebKit and AppKit stop it at the edge.
        guard let topmost,
            let edgeNode = cutBottom && !cutTop ? nodes.max(by: { $0.rect.maxY < $1.rect.maxY }) : topmost
        else { return nil }

        if purpose == .action {
            guard !progress.revealed else { return nil }
            progress.revealed = true
            return .reveal(edgeNode.id)
        }
        if progress.tall {
            if cutTop {
                // Bring its first part (usually its heading) into view; a cut top can't be measured.
                guard !progress.revealedTop else { return nil }
                progress.revealedTop = true
                return .reveal(firstDescendant(of: topmost.id, in: snapshot)?.id ?? topmost.id)
            }
            // Its top shows: anywhere in the upper half will do. Lower down, scrolling it into
            // view brings the top up (Chromium centers it, then its heading comes in). Never a
            // real scroll, which brings the app forward and can tuck the top under a sticky header.
            guard target.y > viewport.midY, !progress.revealed, !progress.revealedTop else { return nil }
            progress.revealed = true
            return .reveal(topmost.id)
        }
        if !progress.revealed {
            progress.revealed = true
            progress.firstCutTop = cutTop
            progress.firstCutBottom = cutBottom
            return .reveal(edgeNode.id)
        }
        guard !progress.scrolled else { return nil }
        if progress.revealMoved {
            // Centering one target can push the others past the opposite edge. They fit
            // together, so one exact scroll brings the whole group back.
            let pushed = (cutTop && !progress.firstCutTop) || (cutBottom && !progress.firstCutBottom)
            guard nodes.count > 1, pushed else { return nil }
        } else {
            // Scrolling into view did nothing. Every engine leaves a target wholly in view where it
            // is, and Chromium's clipped frames make one that only touches the edge (a sticky header,
            // the top of the page, its footer) look cut. So only a frame that runs past the edge
            // means the app ignored the request; anything else stays put, its highlight kept inside.
            guard target.y < viewport.y - edge || target.maxY > viewport.maxY + edge else { return nil }
        }
        progress.scrolled = true
        let amount = shift(for: target, in: viewport, margin: margin, edge: edge)
        return abs(amount) >= unit ? .scroll(amount) : nil
    }

    /// The smallest scroll, in window fractions, that shows a cut target that fits
    /// with `margin` around it, never pushing its top out. A frame that only touches
    /// the edge may be clipped (Chromium), so its unseen part is shown from the top.
    static func shift(for target: NormRect, in viewport: NormRect, margin: Double, edge: Double) -> Double {
        let topAligned = target.y - (viewport.y + margin)
        let bottomAligned = target.maxY - (viewport.maxY - margin)
        if target.maxY > viewport.maxY - edge {
            let known = target.maxY > viewport.maxY + edge
            return min(known ? bottomAligned : topAligned, topAligned)
        }
        if target.y < viewport.y + edge {
            let known = target.y < viewport.y - edge
            return max(known ? topAligned : bottomAligned, bottomAligned)
        }
        return 0
    }

    // MARK: Drawing

    /// Where a highlight of `nodes` is drawn: their union, kept inside their
    /// viewport by the room its outline takes, so it never runs past the edge
    /// of the page or over the browser's toolbar, nor over a sticky header whose
    /// bottom is `coveredTop`.
    static func cueRect(
        for nodes: [AXNode], in snapshot: AXSnapshot, effect: DemoEffect, coveredTop: Double? = nil
    ) -> NormRect? {
        guard let target = union(of: nodes) else { return nil }
        guard var viewport = viewport(of: nodes) else { return target }
        if let coveredTop, coveredTop > viewport.y, coveredTop < viewport.maxY {
            viewport = NormRect(x: viewport.x, y: coveredTop, w: viewport.w, h: viewport.maxY - coveredTop)
        }
        // The spotlight's outline sits 7 points outside the target, the circle 14 more.
        let inset = effect == .draw ? 16.0 : 10.0
        let area = viewport.insetBy(
            dx: inset / max(snapshot.windowFrame.width, 1), dy: inset / max(snapshot.windowFrame.height, 1))
        return target.intersection(area) ?? target
    }

    // MARK: Measuring

    /// How far the content moved up between two looks, in window fractions. Pairs
    /// of the same element decide when they can; otherwise labelled elements that
    /// appear once in both looks do, by their most common movement. Nil when
    /// nothing can tell.
    static func observedShift(from a: AXSnapshot, to b: AXSnapshot, pairs: [(Int, Int)] = []) -> Double? {
        let unit = 1 / max(a.windowFrame.height, 1)
        let paired = pairs.compactMap { pair -> Double? in
            guard let before = a.node(pair.0), let after = b.node(pair.1) else { return nil }
            return edgeShift(before, after, unit: unit)
        }
        if !paired.isEmpty { return median(paired) }

        func key(_ node: AXNode) -> String? {
            node.label.isEmpty || node.viewport == nil ? nil : "\(node.role)|\(node.subrole ?? "")|\(node.label)"
        }
        let after = unique(b, by: key)
        let moves = unique(a, by: key).compactMap { key, before in
            after[key].flatMap { edgeShift(before, $0, unit: unit) }
        }
        return mostCommon(moves.sorted(), tolerance: 2 * unit)
    }

    /// The bottom of page content pinned over the top of `viewport` (a sticky or
    /// fixed header): elements across `target` near its top that stayed put while
    /// the content moved by `moved`. Nil when none did or nothing moved.
    static func pinnedTop(
        from a: AXSnapshot, to b: AXSnapshot, moved: Double, over target: NormRect, in viewport: NormRect,
        excluding ids: Set<Int>
    ) -> Double? {
        let unit = 1 / max(a.windowFrame.height, 1)
        guard abs(moved) >= 8 * unit else { return nil }
        // Labelled elements, and a page's single header or navigation, which often has no label.
        func key(_ node: AXNode) -> String? {
            let landmark = node.subrole?.hasPrefix("AXLandmark") == true
            guard !node.label.isEmpty || landmark else { return nil }
            return "\(node.role)|\(node.subrole ?? "")|\(node.label)"
        }
        let before = unique(a, by: key)
        let band = viewport.y + viewport.h / 4
        let bottoms = unique(b, by: key).compactMap { key, node -> Double? in
            guard !ids.contains(node.id), let old = before[key], node.viewport?.isClose(to: viewport) == true,
                node.rect.h > 2 * edgeTolerance * unit, node.rect.maxY < band, node.rect.x < target.maxX,
                node.rect.maxX > target.x, abs(node.rect.y - old.rect.y) < unit, abs(node.rect.h - old.rect.h) < unit
            else { return nil }
            return node.rect.maxY
        }
        return bottoms.max()
    }

    /// The nodes whose key appears once in `snapshot`.
    private static func unique(_ snapshot: AXSnapshot, by key: (AXNode) -> String?) -> [String: AXNode] {
        var counts: [String: Int] = [:]
        var nodes: [String: AXNode] = [:]
        for node in snapshot.nodes {
            guard let key = key(node) else { continue }
            counts[key, default: 0] += 1
            nodes[key] = node
        }
        return nodes.filter { counts[$0.key] == 1 }
    }

    /// The vertical movement of one element between two looks, from an edge that
    /// isn't at its viewport's edge in either, where Chromium would have clipped it.
    private static func edgeShift(_ before: AXNode, _ after: AXNode, unit: Double) -> Double? {
        let was = trustedEdges(before, unit: unit)
        let now = trustedEdges(after, unit: unit)
        if was.top, now.top { return before.rect.y - after.rect.y }
        if was.bottom, now.bottom { return before.rect.maxY - after.rect.maxY }
        return nil
    }

    private static func trustedEdges(_ node: AXNode, unit: Double) -> (top: Bool, bottom: Bool) {
        let edge = edgeTolerance * unit
        guard let viewport = node.viewport, node.rect.h > 2 * edge else { return (false, false) }
        return (node.rect.y > viewport.y + edge, node.rect.maxY < viewport.maxY - edge)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// The movement most elements agree on. A sticky header stays put while the
    /// page moves, so a tie goes to the movement.
    private static func mostCommon(_ values: [Double], tolerance: Double) -> Double? {
        var best: (count: Int, value: Double)?
        for value in values {
            let group = values.filter { abs($0 - value) <= tolerance }
            let center = median(group)
            if let current = best,
                group.count < current.count || (group.count == current.count && abs(center) <= abs(current.value))
            {
                continue
            }
            best = (group.count, center)
        }
        return best?.value
    }

    // MARK: Structure

    /// The nodes inside `id`, through their chain of containers, in document order.
    static func descendants(of id: Int, in snapshot: AXSnapshot) -> [AXNode] {
        snapshot.nodes.filter { node in
            var container = node.containerID
            for _ in 0..<16 {
                guard let current = container else { return false }
                if current == id { return true }
                container = snapshot.node(current)?.containerID
            }
            return false
        }
    }

    static func firstDescendant(of id: Int, in snapshot: AXSnapshot) -> AXNode? {
        descendants(of: id, in: snapshot).filter(\.rect.isUsable).min { $0.id < $1.id }
    }
}

/// Scrolls demo targets into view before they're highlighted or acted on. The
/// scout and replay frame with the same rules, so a replay's page lines up with
/// the one its later steps were recorded on.
@MainActor
struct DemoFramer {
    struct Timing: Sendable {
        /// Before the first look after a scroll, so Chromium's tree has caught up.
        var minimum = Duration.milliseconds(250)
        var poll = Duration.milliseconds(100)
        var maximum = Duration.milliseconds(1_500)

        static let instant = Timing(minimum: .milliseconds(1), poll: .milliseconds(1), maximum: .milliseconds(100))
    }

    struct Result {
        /// A look taken once scrolling settled.
        var snapshot: AXSnapshot
        /// The targets in `snapshot`; nil when one was lost while scrolling.
        var ids: [Int]?
        /// The other elements followed along, nil where lost.
        var carried: [Int?]
        /// How far the content moved up, in window fractions.
        var shift: Double
        /// Whether framing scrolled, or tried to: the last highlight was cleared, and
        /// this one shows later than its line.
        var scrolled = false
        /// The bottom of a sticky header the scrolling revealed, which a highlight stays below.
        var coveredTop: Double?
    }

    let driver: any DemoDriving
    let source: DemoSource
    var timing = Timing()
    let check: () throws -> Void

    /// At most four scrolls: `AXScrollToVisible` first, with the app in the
    /// background, then for highlights one exact scroll when that can't do it.
    func frame(
        _ ids: [Int], in snapshot: AXSnapshot, for purpose: DemoFraming.Purpose, carrying: [Int?] = []
    ) async throws -> Result {
        var look = snapshot
        var targets: [Int?] = ids
        var carried: [Int?] = carrying
        // Each element as this look describes it, to find it again should a look lose its identity.
        let described = (ids.map { Optional($0) } + carrying).map { id in
            id.flatMap { DemoLocatorFactory.locator(for: $0, in: snapshot) }
        }
        var result = Result(snapshot: snapshot, ids: nil, carried: carrying, shift: 0)
        var progress = DemoFraming.Progress()
        let unit = 1 / max(snapshot.windowFrame.height, 1)
        for _ in 0..<4 {
            let nodes = targets.compactMap { $0.flatMap(look.node) }
            guard nodes.count == ids.count,
                let move = DemoFraming.nextMove(for: nodes, in: look, purpose: purpose, progress: &progress)
            else { break }
            let input: DemoInput =
                switch move {
                case .reveal(let id): .scrollToVisible(ElementHandle(generation: look.generation, id: id))
                case .scroll(let amount):
                    .scrollBy(around: DemoFraming.viewport(of: nodes), points: amount * look.windowFrame.height)
                }
            // The last highlight would stay put while the content scrolls under it.
            if !result.scrolled { driver.show(nil) }
            result.scrolled = true
            do {
                try await driver.perform(input, on: source, pace: .scout) {}
            } catch let error as DemoError where error.wasNotDelivered {
                continue
            }
            try check()
            let settled = try await settle(from: look, following: targets + carried)
            var after = settled.ids
            let pairs = zip(targets, after).compactMap { pair in pair.0.flatMap { a in pair.1.map { (a, $0) } } }
            let moved = DemoFraming.observedShift(from: look, to: settled.snapshot, pairs: pairs) ?? 0
            if case .reveal = move, abs(moved) >= unit { progress.revealMoved = true }
            result.shift += moved
            for index in after.indices where after[index] == nil {
                after[index] = described[index].flatMap {
                    DemoLocatorMatcher.match($0.shifted(by: -result.shift), in: settled.snapshot).nodeID
                }
            }
            if let viewport = DemoFraming.viewport(of: nodes), let target = DemoFraming.union(of: nodes),
                let pinned = DemoFraming.pinnedTop(
                    from: look, to: settled.snapshot, moved: moved, over: target, in: viewport,
                    excluding: Set(after.prefix(ids.count).compactMap { $0 }))
            {
                result.coveredTop = pinned
            }
            look = settled.snapshot
            targets = Array(after.prefix(ids.count))
            carried = Array(after.dropFirst(ids.count))
        }
        let found = targets.compactMap { $0 }
        result.snapshot = look
        result.ids = found.count == ids.count ? found : nil
        result.carried = carried
        return result
    }

    /// Waits until two looks in a row agree on where the targets sit, following
    /// elements from look to look by identity.
    private func settle(from look: AXSnapshot, following ids: [Int?]) async throws -> (
        snapshot: AXSnapshot, ids: [Int?]
    ) {
        let start = ContinuousClock.now
        try await Task.sleep(for: timing.minimum)
        try check()
        var current = try await driver.snapshot(source, waitForContent: false)
        var currentIDs = await follow(ids, from: look, into: current)
        while ContinuousClock.now - start < timing.maximum {
            try await Task.sleep(for: timing.poll)
            try check()
            let next = try await driver.snapshot(source, waitForContent: false)
            let nextIDs = await follow(currentIDs, from: current, into: next)
            if Self.isStill(current, currentIDs, next, nextIDs) { return (next, nextIDs) }
            current = next
            currentIDs = nextIDs
        }
        return (current, currentIDs)
    }

    private func follow(_ ids: [Int?], from a: AXSnapshot, into b: AXSnapshot) async -> [Int?] {
        let present = ids.compactMap { $0 }
        guard !present.isEmpty else { return ids }
        var found = await driver.follow(present.map { ElementHandle(generation: a.generation, id: $0) }, into: b)
            .makeIterator()
        return ids.map { $0 == nil ? nil : found.next() ?? nil }
    }

    /// Only the followed elements count: text changing anywhere else on the page
    /// (a typewriter headline, a rotating tagline) never holds a scroll up.
    private static func isStill(_ a: AXSnapshot, _ aIDs: [Int?], _ b: AXSnapshot, _ bIDs: [Int?]) -> Bool {
        guard b.webContent.map(\.isReady) ?? true else { return false }
        let width = max(b.windowFrame.width, 1)
        let height = max(b.windowFrame.height, 1)
        return zip(aIDs, bIDs).allSatisfy { pair in
            guard let x = pair.0.flatMap(a.node), let y = pair.1.flatMap(b.node) else { return true }
            return abs(x.rect.x - y.rect.x) * width < 1 && abs(x.rect.w - y.rect.w) * width < 1
                && abs(x.rect.y - y.rect.y) * height < 1 && abs(x.rect.h - y.rect.h) * height < 1
        }
    }
}

extension NormRect {
    var maxX: Double { x + w }

    /// The same rectangle, give or take rounding.
    func isClose(to other: NormRect) -> Bool {
        let tolerance = 1e-4
        return abs(x - other.x) < tolerance && abs(y - other.y) < tolerance && abs(w - other.w) < tolerance
            && abs(h - other.h) < tolerance
    }

    /// The overlap of two rectangles, or nil when they don't overlap.
    func intersection(_ other: NormRect) -> NormRect? {
        if x >= other.x, y >= other.y, maxX <= other.maxX, maxY <= other.maxY { return self }
        let minX = max(x, other.x)
        let minY = max(y, other.y)
        let maxX = min(self.maxX, other.maxX)
        let maxY = min(self.maxY, other.maxY)
        guard maxX > minX, maxY > minY else { return nil }
        return NormRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    func insetBy(dx: Double, dy: Double) -> NormRect {
        NormRect(x: x + dx, y: y + dy, w: max(0, w - 2 * dx), h: max(0, h - 2 * dy))
    }
}

extension DemoElementLocator {
    /// The locator for its element after the content moved down by `dy` window fractions.
    func shifted(by dy: Double) -> DemoElementLocator {
        var locator = self
        locator.rect.y += dy
        return locator
    }
}
