import SwiftUI

/// How the step grid fills its width: columns of three, numbered down each
/// column, never scrolling. Steps that don't fit go behind an overflow cell.
struct StepGridLayout: Equatable {
    static let rows = 3
    static let minimumColumnWidth: CGFloat = 140
    static let maximumColumnWidth: CGFloat = 260
    static let columnGap: CGFloat = 12

    var columns: Int
    var columnWidth: CGFloat
    /// Cells shown before the overflow cell, or all of them.
    var visible: Int
    /// Cells behind the overflow cell.
    var hidden: Int

    init(cells: Int, width: CGFloat) {
        let maximumColumns = max(1, Int((width + Self.columnGap) / (Self.minimumColumnWidth + Self.columnGap)))
        let needed = max(1, (cells + Self.rows - 1) / Self.rows)
        columns = min(needed, maximumColumns)
        columnWidth = max(
            0, min(Self.maximumColumnWidth, (width - Self.columnGap * CGFloat(columns - 1)) / CGFloat(columns)))
        if needed > maximumColumns {
            visible = maximumColumns * Self.rows - 1
            hidden = cells - visible
        } else {
            visible = cells
            hidden = 0
        }
    }
}

/// The demo's steps in a 3-row grid, with progress drawn on the markers.
struct DemoStepGrid: View {
    let cells: [StepCellModel]
    let isEditable: Bool
    let edit: (UUID) -> Void
    @State private var width: CGFloat = 0

    private enum Slot: Identifiable {
        case cell(StepCellModel)
        case overflow

        var id: String {
            switch self {
            case .cell(let cell): cell.id
            case .overflow: "overflow"
            }
        }
    }

    var body: some View {
        let layout = StepGridLayout(cells: cells.count, width: width)
        let slots = cells.prefix(layout.visible).map(Slot.cell) + (layout.hidden > 0 ? [.overflow] : [])
        HStack(alignment: .top, spacing: StepGridLayout.columnGap) {
            ForEach(0..<layout.columns, id: \.self) { column in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(slots.dropFirst(column * StepGridLayout.rows).prefix(StepGridLayout.rows)) { slot in
                        switch slot {
                        case .cell(let cell):
                            StepCell(cell: cell, isEditable: isEditable, edit: edit)
                        case .overflow:
                            OverflowCell(
                                cells: cells, hidden: Array(cells.dropFirst(layout.visible)), isEditable: isEditable,
                                edit: edit)
                        }
                    }
                }
                .frame(width: layout.columnWidth, alignment: .leading)
            }
        }
        // minWidth 0 reports the width on offer, not the columns', so the grid can narrow again.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
    }
}

/// One step: its marker, its title, and a pencil on hover when Edit Demo can open there.
struct StepCell: View {
    let cell: StepCellModel
    let isEditable: Bool
    let edit: (UUID) -> Void
    /// Steps hidden behind this one, when it stands in for the overflow cell.
    var moreCount: Int?
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if isEditable, let stepID = cell.stepID {
            Button {
                edit(stepID)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovering = hovering }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cell.accessibilityLabel)
            .accessibilityValue(cell.accessibilityValue)
            .accessibilityHint("Opens Edit Demo at this step")
            .accessibilityAddTraits(.isButton)
        } else {
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cell.accessibilityLabel)
                .accessibilityValue(cell.accessibilityValue)
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            StepMarker(state: cell.state, number: cell.number)
            title
            Spacer(minLength: 0)
            if let moreCount {
                Text("+\(moreCount)").font(.caption).foregroundStyle(.secondary)
            }
            if isHovering, isEditable {
                Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(height: 18)
        .background {
            if isHovering, isEditable {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(contrast == .increased ? 0.12 : 0.06))
                    .padding(.horizontal, -4)
                    .padding(.vertical, -1)
            }
        }
        .contentShape(Rectangle())
        .help(cell.help ?? cell.title)
    }

    private var title: some View {
        let isStressed = cell.state == .current || cell.state == .testing
        return Text(cell.title)
            .font(isStressed ? .callout.weight(.semibold) : .callout)
            .foregroundStyle(titleStyle)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var titleStyle: HierarchicalShapeStyle {
        switch cell.state {
        case .recording, .passed, .done: .secondary
        case .planned: contrast == .increased ? .secondary : .tertiary
        default: .primary
        }
    }
}

/// A step's 16 pt marker. Accent means progress, green a passed test, orange a stop.
struct StepMarker: View {
    let state: StepCellModel.State
    let number: Int
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            switch state {
            case .idle, .upcoming, .recorded:
                Circle().fill(.primary.opacity(contrast == .increased ? 0.20 : 0.08))
                numeral.foregroundStyle(.secondary)
            case .recording:
                ProgressView().controlSize(.mini)
            case .planned:
                Circle()
                    .strokeBorder(
                        contrast == .increased ? HierarchicalShapeStyle.secondary : .tertiary,
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            case .needsApproval:
                Image(systemName: "hand.raised.fill").font(.caption).foregroundStyle(.orange)
            case .passed:
                Circle().fill(Color.green)
                check
            case .testing:
                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                ProgressView().controlSize(.mini).scaleEffect(0.8)
            case .current:
                Circle().fill(Color.accentColor.opacity(0.15))
                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                numeral.foregroundStyle(Color.accentColor)
            case .done:
                Circle().fill(Color.accentColor)
                check
            case .failed:
                Circle().fill(Color.orange.opacity(0.15))
                Circle().strokeBorder(Color.orange, lineWidth: 1.5)
                Image(systemName: "exclamationmark").font(.caption2.bold()).foregroundStyle(.orange)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private var numeral: some View {
        Text("\(number)").font(.caption2.monospacedDigit().weight(.semibold))
    }

    private var check: some View {
        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
    }
}

/// The last visible cell when steps don't fit. It keeps a run's current or
/// failed step in view, and opens every step in a popover.
private struct OverflowCell: View {
    let cells: [StepCellModel]
    let hidden: [StepCellModel]
    let isEditable: Bool
    let edit: (UUID) -> Void
    @State private var showsAll = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var moreSteps: String { hidden.count == 1 ? "1 more step" : "\(hidden.count) more steps" }

    var body: some View {
        Button {
            showsAll = true
        } label: {
            if let position = hidden.first(where: \.isRunPosition) {
                StepCell(cell: position, isEditable: false, edit: { _ in }, moreCount: hidden.count - 1)
            } else {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(.primary.opacity(contrast == .increased ? 0.20 : 0.08))
                        Image(systemName: "ellipsis").font(.system(size: 8, weight: .bold))
                    }
                    .frame(width: 16, height: 16)
                    Text(moreSteps)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .frame(height: 18)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(moreSteps)
        .accessibilityHint("Shows all \(cells.count) steps")
        .accessibilityAddTraits(.isButton)
        .popover(isPresented: $showsAll, arrowEdge: .bottom) {
            StepOverflowPopover(cells: cells, isEditable: isEditable) { step in
                showsAll = false
                edit(step)
            }
        }
    }
}

/// Every step, in the same cell style, for when the grid can't show them all.
struct StepOverflowPopover: View {
    let cells: [StepCellModel]
    let isEditable: Bool
    let edit: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All \(cells.count) Steps").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(cells) { cell in
                        StepCell(cell: cell, isEditable: isEditable, edit: edit)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: min(CGFloat(cells.count) * 20, 270))
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}
