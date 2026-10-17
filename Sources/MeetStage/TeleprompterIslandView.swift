import AppKit
import SwiftUI

/// The teleprompter island: where the demo is beside the camera, the line to
/// say below it, and the demo's controls under the line. `chrome` says what
/// shape to draw and which content to show; everything else comes from the
/// session, through the same model as the demo panel.
struct TeleprompterIslandView: View {
    @ObservedObject var demo: DemoSession
    /// Its state can change what the panel offers.
    @ObservedObject var listener: SpeechListener
    let chrome: IslandChrome

    init(demo: DemoSession, chrome: IslandChrome) {
        self.demo = demo
        listener = demo.prompter.listener
        self.chrome = chrome
    }

    var body: some View {
        // The panel's content reads the app's windows and hashes the demo, so it's
        // built when the session changes, not for every word the prompter hears.
        IslandRoot(
            demo: demo, chrome: chrome, panel: .make(DemoPanelInputs(session: demo, stagePaused: demo.stagePaused)))
    }
}

/// The island itself. Each word heard redraws it with the panel content it was
/// given, which only changes with the session.
private struct IslandRoot: View {
    @ObservedObject var demo: DemoSession
    @ObservedObject var prompter: PresenterPrompter
    /// Only the listener's state is published; its levels redraw just the meter.
    @ObservedObject var listener: SpeechListener
    let chrome: IslandChrome
    let panel: DemoPanelContent
    /// What each mode showed as the island left it, so content fading out
    /// during a morph keeps its look instead of switching to the next mode's.
    @State private var leaving: [IslandMode: IslandContent] = [:]

    init(demo: DemoSession, chrome: IslandChrome, panel: DemoPanelContent) {
        self.demo = demo
        prompter = demo.prompter
        listener = demo.prompter.listener
        self.chrome = chrome
        self.panel = panel
    }

    var body: some View {
        let live = IslandContent.make(IslandInputs(session: demo, panel: panel))
        let content = live.mode == chrome.contentMode ? live : leaving[chrome.contentMode] ?? live
        let shape = chrome.shape
        ZStack(alignment: .top) {
            IslandShape(shoulder: shape.shoulder, bottomRadius: shape.bottomRadius)
                .fill(.black)
                .overlay {
                    IslandEdge(shoulder: shape.shoulder, bottomRadius: shape.bottomRadius, stopped: content.stoppedEdge)
                }
                .frame(width: shape.size.width, height: shape.size.height)
            if let layout = chrome.layout {
                Group {
                    switch chrome.contentMode {
                    case .expanded:
                        ExpandedIsland(
                            content: content, layout: layout, followsVoice: prompter.followsVoice,
                            voice: listener.state, demo: demo, prompter: prompter)
                    case .compact:
                        CompactIsland(content: content, layout: layout, demo: demo)
                    }
                }
                .frame(width: chrome.contentSize.width, height: chrome.contentSize.height, alignment: .top)
                .opacity(chrome.contentOpacity)
                .allowsHitTesting(chrome.contentOpacity > 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .contextMenu { IslandOptions(demo: demo, extras: content.extras) }
        .onChange(of: live) { old, new in
            if old.mode != new.mode { leaving[old.mode] = old }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Teleprompter")
    }
}

// MARK: - Shapes

/// Increase Contrast's faint edge, or an orange one when the demo stopped. It
/// runs down the sides and along the bottom only, so the top stays one with
/// the notch and the menu bar.
struct IslandEdge: View {
    let shoulder: CGFloat
    let bottomRadius: CGFloat
    let stopped: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let island = IslandShape(shoulder: shoulder, bottomRadius: bottomRadius)
        // Strokes are twice as wide as they look: the clip keeps the inner half.
        ZStack {
            if contrast == .increased {
                island.stroke(.white.opacity(0.35), lineWidth: 2)
            }
            island.stroke(.orange, lineWidth: 3)
                .opacity(stopped ? 1 : 0)
        }
        .clipShape(island)
        .mask {
            VStack(spacing: 0) {
                Color.clear.frame(height: shoulder)
                Color.black
            }
        }
        .animation(.easeOut(duration: 0.2), value: stopped)
        .allowsHitTesting(false)
    }
}

// MARK: - Expanded

/// The line to read: the band beside the camera, the line in rows, and the footer.
private struct ExpandedIsland: View {
    let content: IslandContent
    let layout: IslandLayout
    let followsVoice: Bool
    let voice: SpeechListener.State
    let demo: DemoSession
    @ObservedObject var prompter: PresenterPrompter
    /// The place of the line shown last, so the next one knows which way to slide.
    @State private var shownOrder: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private struct LineIdentity: Hashable {
        var demo: UUID?
        var order: Int
        var words: [String]
    }

    var body: some View {
        VStack(spacing: 0) {
            IslandBand(content: content, width: layout.width, gap: layout.slotGap, inset: 28) {
                if let next = content.next { IslandUpNext(next: next) }
            }
            .frame(height: layout.band)
            line
                .padding(.top, 6)
            footer
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(width: layout.width, height: layout.height, alignment: .top)
    }

    // MARK: Line

    /// The opening first, then each step, then the closing.
    private static func order(of line: PresenterPrompter.Line?) -> Int {
        switch line {
        case .opening: -1
        case .step(let index): index
        case .closing, nil: .max
        }
    }

    private var line: some View {
        let order = Self.order(of: prompter.line)
        let identity = LineIdentity(demo: demo.demo?.id, order: order, words: prompter.follower.displayWords)
        return ZStack(alignment: .topLeading) {
            lineBody
                .id(identity)
                .transition(lineTransition(order: order))
        }
        .frame(width: layout.textWidth, height: layout.viewport, alignment: .topLeading)
        .clipped()
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.35), value: identity)
        .onChange(of: order, initial: true) { shownOrder = order }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current line")
        .accessibilityValue(lineValue)
    }

    /// A new line comes up from below as the demo moves on, and down from above when it goes back.
    private func lineTransition(order: Int) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance = 0.6 * layout.advance
        let rise = order >= (shownOrder ?? order) ? distance : -distance
        let prompter = self.prompter
        return .asymmetric(
            insertion: .offset(y: rise).combined(with: .opacity),
            removal: .modifier(
                active: LineSlide { Self.order(of: prompter.line) >= order ? -distance : distance },
                identity: LineSlide { 0 }
            )
            .combined(with: .opacity))
    }

    /// The timed hold the line follows while voice is off.
    private var timedHold: (start: Date, seconds: Double)? {
        if case .timed(let start, let seconds) = content.meter { return (start, seconds) }
        return nil
    }

    @ViewBuilder private var lineBody: some View {
        let raised = contrast == .increased
        switch content.body {
        case .line(let words, let dim):
            // Voice off, the reading position follows the hold. The rows stay in one
            // TimelineView either way, so they keep their place when the hold ends.
            let hold = timedHold
            TimelineView(.animation(minimumInterval: 0.25, paused: hold == nil)) { context in
                let count = Double(prompter.follower.displayWords.count)
                let active =
                    hold.map { Int(context.date.timeIntervalSince($0.start) / max($0.seconds, 0.1) * count) }
                    ?? activeWord(words)
                rows(words, dim: dim, active: active)
            }
        case .noLine(let dim):
            // SF Rounded has no italic, so this one line is in SF Pro.
            Text(PresenterPrompter.noLineText)
                .font(.system(size: layout.fontSize * 0.75, weight: .medium))
                .italic()
                .foregroundStyle(.white.opacity((raised ? 0.75 : 0.55) * (dim ? 0.6 : 1)))
        case .message(let text):
            Text(text)
                .font(.system(size: layout.fontSize * 0.65, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(raised ? 0.8 : 0.6))
        case nil:
            EmptyView()
        }
    }

    private func rows(_ words: IslandContent.Words, dim: Bool, active: Int) -> some View {
        ScriptRowsView(
            inputs: .init(
                words: prompter.follower.displayWords, shown: prompter.showCount, spoken: prompter.follower.spoken,
                active: min(max(0, active), max(0, prompter.follower.displayWords.count - 1)), style: words,
                dim: dim, size: layout.fontSize, textWidth: layout.textWidth, advance: layout.advance,
                viewport: layout.viewport, anchor: layout.anchor)
        )
        .equatable()
    }

    /// The word the rows keep in view: the next one to say while listening, else the last one said.
    private func activeWord(_ words: IslandContent.Words) -> Int {
        let follower = prompter.follower
        let last = follower.displayWords.count - 1
        return switch words {
        case .followed(marksNext: true): follower.nextWord ?? last
        case .allSaid: last
        case .uniform, .followed: min(follower.spoken, last)
        }
    }

    private var lineValue: String {
        switch content.body {
        case .line: prompter.follower.displayWords.joined(separator: " ")
        case .noLine: PresenterPrompter.noLineText
        case .message(let text): text
        case nil: ""
        }
    }

    // MARK: Footer

    /// How much of the line is said, for the meter's lit bars.
    private var progress: Double {
        let follower = prompter.follower
        if content.meter == .full || follower.isComplete { return 1 }
        return Double(follower.spoken) / Double(max(1, follower.displayWords.count))
    }

    private var footer: some View {
        HStack(spacing: 0) {
            // Ticks through a timed hold, so VoiceOver reads its countdown and progress as they are now.
            TimelineView(.animation(minimumInterval: 0.5, paused: timedHold == nil)) { context in
                HStack(spacing: 8) {
                    if content.meter != .hidden {
                        IslandMeter(meter: content.meter, progress: progress, levels: prompter.listener.levels)
                            .frame(width: layout.meterWidth, height: 24)
                    }
                    IslandStatus(status: content.status, heard: prompter.heardTail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(statusText(at: context.date))
                .accessibilityValue(
                    content.meter == .hidden
                        ? "" : "\(Int((meterProgress(at: context.date) * 100).rounded())) percent of the line"
                )
                .accessibilityHidden(content.status == .none && content.meter == .hidden)
            }
            HStack(spacing: 6) {
                ForEach(Array(content.slots.enumerated()), id: \.offset) { index, action in
                    slot(action, isPrimary: index == 2)
                }
            }
            .padding(.leading, 10)
            HStack(spacing: 6) {
                MicButton(
                    followsVoice: followsVoice, voice: voice, language: prompter.listener.language,
                    toggle: { demo.followsVoice.toggle() })
                IslandOptionsButton(demo: demo, extras: content.extras)
            }
            .padding(.leading, 12)
        }
        .frame(width: layout.textWidth, height: 28)
    }

    /// The meter's lit share at `date`, as VoiceOver reads it.
    private func meterProgress(at date: Date) -> Double {
        switch content.meter {
        case .timed(let start, let seconds): min(1, date.timeIntervalSince(start) / max(seconds, 0.1))
        case .dots, .hidden: 0
        case .voice, .full: progress
        }
    }

    private func statusText(at date: Date) -> String {
        switch content.status {
        case .none: ""
        case .text(let text, _, _): text
        case .heard: prompter.heardTail.isEmpty ? "Listening" : prompter.heardTail.joined(separator: " ")
        case .countdown(let start, let seconds): IslandStatus.countdown(start: start, seconds: seconds, at: date)
        }
    }

    private func slot(_ action: PanelAction, isPrimary: Bool) -> some View {
        let symbol = action.islandSymbol
        return Button {
            action.id.perform(on: demo)
        } label: {
            // Play's triangle looks off center when it is centered.
            Image(systemName: symbol)
                .offset(x: symbol == "play.fill" ? 1 : 0)
        }
        .buttonStyle(IslandButtonStyle(isProminent: isPrimary && action.role == .forward))
        .disabled(!action.isEnabled)
        .help(action.help)
        .accessibilityLabel(action.title)
    }
}

/// Moves a line as it comes or goes. The offset is read as the line moves, so
/// a line leaving goes the way the demo went, which wasn't known when its
/// transition was set.
private struct LineSlide: ViewModifier {
    let offset: () -> CGFloat

    func body(content: Content) -> some View {
        content.offset(y: offset())
    }
}

// MARK: - Compact

/// Nothing to read: a strip as tall as the menu bar, saying what the demo is
/// doing beside the camera, with the options on the other side.
private struct CompactIsland: View {
    let content: IslandContent
    let layout: IslandLayout
    let demo: DemoSession

    var body: some View {
        IslandBand(content: content, width: layout.compactWidth, gap: layout.slotGap, inset: 18) {
            IslandOptionsButton(demo: demo, extras: content.extras, diameter: 20)
        }
        .frame(height: layout.band)
    }
}

// MARK: - Band

/// The strip beside the camera: where the demo is on the left, and what comes
/// next or the options on the right. Neither side reaches behind the camera.
private struct IslandBand<Trailing: View>: View {
    let content: IslandContent
    /// The island's width.
    let width: CGFloat
    /// The camera between the two sides.
    let gap: CGFloat
    /// From the island's edge to each side.
    let inset: CGFloat
    @ViewBuilder let trailing: Trailing

    var body: some View {
        // Each side stops 8 points short of the camera, which is as black as the island.
        let side = max(0, (width - gap) / 2 - 8 - inset)
        HStack(spacing: 0) {
            IslandPlace(content: content)
                .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            trailing
                .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, inset)
        .frame(width: width)
    }
}

/// Where the demo is: a state glyph, the step's position, and its title.
private struct IslandPlace: View {
    let content: IslandContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let raised = contrast == .increased
        let change: Animation = reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.25)
        HStack(spacing: 4) {
            if let mark = content.mark {
                IslandMarkGlyph(mark: mark)
                    .transition(.opacity)
            }
            if let position = content.position {
                Text(position)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(raised ? 0.8 : 0.6))
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .fixedSize()
            }
            Text(content.place)
                .foregroundStyle(.white.opacity(raised ? 1 : 0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .animation(change, value: content.position)
        .animation(change, value: content.place)
        .animation(change, value: content.mark)
        .help(content.placeHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.placeAccessibility)
    }
}

/// The glyph before the band's place: the only colour in the band.
private struct IslandMarkGlyph: View {
    let mark: IslandContent.Mark

    var body: some View {
        Group {
            switch mark {
            case .spinner:
                ProgressView()
                    .controlSize(.mini)
            case .paused:
                Image(systemName: "pause.fill")
                    .foregroundStyle(.white.opacity(0.85))
            case .stopped:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .notAtStart:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 12, height: 12)
    }
}

/// "Next" and the next step's title, or "Last step".
private struct IslandUpNext: View {
    let next: IslandContent.Upcoming
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let raised = contrast == .increased
        let quiet = raised ? 0.7 : 0.5
        HStack(spacing: 4) {
            if let label = next.label {
                Text(label)
                    .foregroundStyle(.white.opacity(quiet))
                    .fixedSize()
            }
            // "Last step" stays as quiet as the label it stands in for.
            Text(next.title)
                .foregroundStyle(.white.opacity(next.label == nil ? quiet : raised ? 0.9 : 0.75))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .help(next.accessibilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(next.accessibilityLabel)
    }
}

// MARK: - Rows

/// The line's words in rows, Textream style: words already said dim, the next
/// one is underlined while listening, and the row being read stays second from
/// the top with the one before it still in view. The position only moves
/// forward, so a recognizer revising what it heard can't scroll the line back.
struct ScriptRowsView: View, Equatable {
    struct Inputs: Equatable {
        var words: [String]
        /// `PresenterPrompter.showCount`: a line shown again reads from its start.
        var shown: Int
        var spoken: Int
        /// The word the reading position follows.
        var active: Int
        var style: IslandContent.Words
        var dim: Bool
        var size: Double
        var textWidth: CGFloat
        var advance: CGFloat
        var viewport: CGFloat
        var anchor: Int
    }

    let inputs: Inputs
    /// How far the line has scrolled, in the layout it was broken for.
    @State private var reached: Reached?
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Reached: Equatable {
        /// The size, width and weight the rows were broken for.
        var layout: [Double]
        var shown: Int
        var top: Int
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.inputs == rhs.inputs }

    var body: some View {
        let bold = legibilityWeight == .bold
        let font = IslandType.font(size: inputs.size, bold: bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let rows = ScriptRows.make(
            words: inputs.words, width: inputs.textWidth,
            space: (" " as NSString).size(withAttributes: attributes).width
        ) { ($0 as NSString).size(withAttributes: attributes).width }
        // A new size, width or weight breaks the rows differently, and a line shown
        // again reads from its start, so the position starts over.
        let layout = [inputs.size, inputs.textWidth, bold ? 1 : 0]
        let activeRow = rows.row(of: inputs.active)
        let top = ScriptRows.top(
            activeRow: activeRow, rowCount: rows.rows.count, anchor: inputs.anchor,
            previous: reached.flatMap { $0.layout == layout && $0.shown == inputs.shown ? $0.top : nil })
        let continues = CGFloat(rows.rows.count - top) * inputs.advance > inputs.viewport
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.rows.indices, id: \.self) { index in
                Text(text(of: rows.rows[index]))
                    .font(.system(size: inputs.size, weight: bold ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: inputs.advance, alignment: .top)
            }
        }
        .animation(.easeOut(duration: 0.15), value: inputs.spoken)
        .offset(y: -CGFloat(top) * inputs.advance)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: top)
        .frame(width: inputs.textWidth, height: inputs.viewport, alignment: .topLeading)
        .clipped()
        .mask { fades(top: ScriptRows.fadesTop(top: top, activeRow: activeRow), bottom: continues) }
        .onChange(of: Reached(layout: layout, shown: inputs.shown, top: top), initial: true) { _, new in
            reached = new
        }
    }

    private func text(of row: [ScriptRows.Piece]) -> AttributedString {
        var text = AttributedString()
        for (index, piece) in row.enumerated() {
            // Pieces of one long word join; the space stays out of the next word's underline.
            if index > 0, row[index - 1].word != piece.word { text.append(AttributedString(" ")) }
            var part = AttributedString(piece.text)
            part.foregroundColor = .white.opacity(opacity(of: piece.word))
            if case .followed(marksNext: true) = inputs.style, piece.word == inputs.spoken {
                part.underlineStyle = Text.LineStyle(pattern: .solid, color: .accentColor)
            }
            text.append(part)
        }
        return text
    }

    private func opacity(of word: Int) -> Double {
        let raised = contrast == .increased
        let said =
            switch inputs.style {
            case .uniform: false
            case .followed: word < inputs.spoken
            case .allSaid: true
            }
        let opacity = said ? (raised ? 0.55 : 0.34) : 1
        return inputs.dim ? opacity * (raised ? 0.8 : 0.6) : opacity
    }

    /// Rows cut by the viewport's edges fade out, so the line reads as going on.
    /// The bottom fade is short enough never to reach the row being read.
    private func fades(top: Bool, bottom: Bool) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(top ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(bottom ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 20)
        }
    }
}

// MARK: - Meter

/// A level meter that is also the line's progress: bar heights follow the
/// voice, and lit bars show how much of the line is said or how much of a
/// timed hold has passed.
private struct IslandMeter: View {
    let meter: IslandContent.Meter
    let progress: Double
    let levels: LevelHistory

    var body: some View {
        switch meter {
        case .voice, .full:
            VoiceBars(levels: levels, progress: progress)
        case .timed(let start, let seconds):
            TimelineView(.periodic(from: start, by: 0.05)) { context in
                MeterBars(levels: [], progress: min(1, context.date.timeIntervalSince(start) / max(seconds, 0.1)))
            }
        case .dots:
            MeterBars(levels: [], progress: 0)
        case .hidden:
            EmptyView()
        }
    }
}

/// Reads the microphone's levels here, so only the meter redraws twenty times a second.
private struct VoiceBars: View {
    let levels: LevelHistory
    let progress: Double

    var body: some View {
        MeterBars(levels: levels.samples, progress: progress)
    }
}

/// Bars 3 points wide with 2-point gaps, as many as fit, oldest on the left.
private struct MeterBars: View {
    let levels: [Float]
    let progress: Double
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let unlit = Color.white.opacity(contrast == .increased ? 0.32 : 0.18)
        // Reduce Motion keeps flat dots; only the lit share changes.
        let levels = reduceMotion ? [] : levels
        Canvas { context, size in
            let count = Int((size.width + 2) / 5)
            let lit = Int((progress * Double(count)).rounded())
            let recent = levels.suffix(count)
            let padding = count - recent.count
            for index in 0..<count {
                let level = index < padding ? 0 : CGFloat(recent[recent.startIndex + index - padding])
                let height = max(3, level * 20)
                let bar = CGRect(x: CGFloat(index) * 5, y: (size.height - height) / 2, width: 3, height: height)
                context.fill(
                    Path(roundedRect: bar, cornerRadius: 1.5),
                    with: .color(index < lit ? Color.accentColor.opacity(0.95) : unlit))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Status

/// Why the demo waits, the last words heard, or a timed hold's countdown.
private struct IslandStatus: View {
    let status: IslandContent.Status
    let heard: [String]
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func countdown(start: Date, seconds: Double, at date: Date) -> String {
        "Moves on in \(max(0, Int((seconds - date.timeIntervalSince(start)).rounded(.up)))) s"
    }

    var body: some View {
        let raised = contrast == .increased
        let plain = Color.white.opacity(raised ? 0.75 : 0.5)
        Group {
            switch status {
            case .none:
                EmptyView()
            case .text(let text, let tone, let help):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if tone == .warning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(text)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .foregroundStyle(tone == .warning ? Color.orange.opacity(0.9) : plain)
                .help(help ?? text)
            case .heard:
                if heard.isEmpty {
                    Text("Listening")
                        .foregroundStyle(.white.opacity(raised ? 0.55 : 0.35))
                } else {
                    let words = heard.joined(separator: " ")
                    Text(words)
                        .foregroundStyle(plain)
                        .lineLimit(2)
                        .truncationMode(.head)
                        .help(words)
                }
            case .countdown(let start, let seconds):
                TimelineView(.periodic(from: start, by: 1)) { context in
                    let text = Self.countdown(start: start, seconds: seconds, at: context.date)
                    Text(text)
                        .foregroundStyle(plain)
                        .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                        .animation(.default, value: text)
                }
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
    }
}

// MARK: - Controls

/// Follow my voice, showing whether the microphone hears the presenter.
private struct MicButton: View {
    let followsVoice: Bool
    let voice: SpeechListener.State
    let language: String?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            if followsVoice, voice.isPreparing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: symbol)
            }
        }
        .buttonStyle(IslandButtonStyle(tint: tint))
        .help(help)
        .accessibilityLabel(followsVoice ? "Stop following my voice" : "Follow my voice")
        .accessibilityValue(value)
    }

    private var symbol: String {
        guard followsVoice else { return "mic.slash" }
        if case .unavailable = voice { return "mic.badge.xmark" }
        return "mic.fill"
    }

    private var tint: Color {
        guard followsVoice else { return .white.opacity(0.6) }
        return switch voice {
        case .listening: .accentColor
        case .unavailable: .orange
        case .preparing: .white.opacity(0.8)
        case .off: .white.opacity(0.85)
        }
    }

    private var value: String {
        guard followsVoice else { return "" }
        return switch voice {
        case .listening: "Listening"
        case .preparing(let text): text
        case .unavailable(let reason): "Unavailable: \(reason)"
        case .off: ""
        }
    }

    private var help: String {
        if case .unavailable(let reason) = voice { return reason }
        let language = language.map { " Listening for \($0)." } ?? ""
        return followsVoice
            ? "Following your voice on this Mac. Each step moves on when you finish its line." + language
            : "Follow my voice: highlight the next word and move on when you finish each line."
    }
}

/// Teleprompter options, as a button shaped like the island's others.
private struct IslandOptionsButton: View {
    let demo: DemoSession
    let extras: [PanelAction]
    var diameter: CGFloat = 28

    var body: some View {
        Menu {
            IslandOptions(demo: demo, extras: extras)
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(IslandButtonStyle(diameter: diameter))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Teleprompter options")
        .accessibilityLabel("Teleprompter options")
    }
}

/// The options menu, which is also the island's context menu: text size, the
/// panel's other actions for this state, and Hide Teleprompter.
private struct IslandOptions: View {
    let demo: DemoSession
    let extras: [PanelAction]

    var body: some View {
        let prompter = demo.prompter
        Button("Larger Text") { prompter.fontSize = min(48, prompter.fontSize + 2) }
            .disabled(prompter.fontSize >= 48)
        Button("Smaller Text") { prompter.fontSize = max(16, prompter.fontSize - 2) }
            .disabled(prompter.fontSize <= 16)
        if !extras.isEmpty {
            Divider()
            ForEach(extras) { action in
                Button(action.title) { action.id.perform(on: demo) }
                    .disabled(!action.isEnabled)
                    .help(action.help)
            }
        }
        Divider()
        Button("Hide Teleprompter", action: demo.hideTeleprompter)
    }
}

/// The island's one control: a circle, the same size for every button, so
/// nothing in the footer competes by size. A forward primary is filled with
/// the accent color; Pause Demo stays quiet. Disabled buttons dim in place.
struct IslandButtonStyle: ButtonStyle {
    var diameter: CGFloat = 28
    var isProminent = false
    /// The glyph's color instead of white, for the microphone's state.
    var tint: Color?
    /// A capsule as tall as the circle and as wide as its label, for a text button.
    var fitsLabel = false

    func makeBody(configuration: Configuration) -> some View {
        IslandButton(configuration: configuration, style: self)
    }
}

private struct IslandButton: View {
    let configuration: ButtonStyleConfiguration
    let style: IslandButtonStyle
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let raised = contrast == .increased
        let pressed = configuration.isPressed
        let prominent = style.isProminent && isEnabled
        let fill: Color =
            if prominent {
                .accentColor.opacity(pressed ? 0.8 : 1)
            } else if !isEnabled {
                .white.opacity(0.06)
            } else {
                .white.opacity(pressed ? 0.28 : isHovered ? 0.2 : raised ? 0.22 : 0.12)
            }
        let glyph: Color =
            if prominent {
                .white
            } else if !isEnabled {
                .white.opacity(raised ? 0.45 : 0.3)
            } else {
                style.tint ?? .white.opacity(raised ? 1 : 0.85)
            }
        // A capsule in a square frame is the circle.
        configuration.label
            .font(.system(size: style.diameter >= 28 ? 12 : 10, weight: .semibold))
            .foregroundStyle(glyph)
            .padding(.horizontal, style.fitsLabel ? 14 : 0)
            .frame(width: style.fitsLabel ? nil : style.diameter, height: style.diameter)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: pressed)
            .onHover { isHovered = $0 }
    }
}
