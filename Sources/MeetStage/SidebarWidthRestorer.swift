import AppKit
import SwiftUI

struct SidebarWidthRestorer: NSViewRepresentable {
    var defaults: UserDefaults = .standard

    func makeNSView(context: Context) -> SidebarObserver {
        let observer = SidebarObserver()
        observer.defaults = defaults
        return observer
    }
    func updateNSView(_ nsView: SidebarObserver, context: Context) {}
}

final class SidebarObserver: NSView {
    var defaults: UserDefaults = .standard
    private static let widthKey = "BetterMeets.sidebarWidth"
    private weak var splitView: NSSplitView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            NotificationCenter.default.removeObserver(self)
            splitView = nil
            return
        }
        DispatchQueue.main.async { [weak self] in self?.restoreWidth() }
    }

    private func restoreWidth() {
        guard window != nil, splitView == nil else { return }
        var ancestor = superview
        while let view = ancestor {
            if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count == 2 {
                splitView = split
                let savedWidth = defaults.double(forKey: Self.widthKey)
                let width = savedWidth > 0 ? savedWidth : WorkspaceMetrics.sidebarWidth
                split.setPosition(min(320, max(200, width)), ofDividerAt: 0)
                NotificationCenter.default.addObserver(
                    self, selector: #selector(saveWidth),
                    name: NSSplitView.didResizeSubviewsNotification, object: split
                )
                return
            }
            ancestor = view.superview
        }
    }

    @objc private func saveWidth() {
        guard let width = splitView?.arrangedSubviews.first?.frame.width, width >= 200 else { return }
        defaults.set(width, forKey: Self.widthKey)
    }
}
