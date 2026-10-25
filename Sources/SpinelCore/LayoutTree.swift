import CoreGraphics

public enum LayoutMode: String, Codable, Sendable {
    /// Binary space partitioning: each new window splits the focused one along its longer side.
    case bsp
    /// Every window fills the whole area; focus cycles through them.
    case monocle
}

/// A binary space-partitioning tree for one (Space, display) pair.
/// Leaves hold windows; inner nodes hold a split axis and ratio.
public final class LayoutTree {
    final class Node {
        weak var parent: Node?
        var window: WindowID?
        var axis: Axis = .horizontal
        var ratio: Double = 0.5
        var first: Node?
        var second: Node?

        init(window: WindowID) {
            self.window = window
        }

        init(axis: Axis, ratio: Double, first: Node, second: Node) {
            self.axis = axis
            self.ratio = ratio
            self.first = first
            self.second = second
            first.parent = self
            second.parent = self
        }

        var leaves: [Node] {
            if window != nil { return [self] }
            return (first?.leaves ?? []) + (second?.leaves ?? [])
        }
    }

    private static let ratioRange = 0.05...0.95

    private var root: Node?

    public init() {}

    public var isEmpty: Bool { root == nil }

    /// Windows in tree order (left-to-right / top-to-bottom).
    public var windows: [WindowID] { root?.leaves.compactMap(\.window) ?? [] }

    public func contains(_ id: WindowID) -> Bool { leaf(id) != nil }

    private func leaf(_ id: WindowID) -> Node? {
        root?.leaves.first { $0.window == id }
    }

    // MARK: - Mutation

    /// Splits the leaf holding `target` (or the last leaf) along its longer side and puts `id`
    /// in the second half, dwindle-style.
    public func insert(_ id: WindowID, near target: WindowID? = nil, in bounds: CGRect, gaps: Gaps = .zero) {
        guard !contains(id) else { return }
        let newLeaf = Node(window: id)
        guard let root else {
            self.root = newLeaf
            return
        }
        let targetLeaf = target.flatMap(leaf) ?? root.leaves.last!
        let rect = nodeRects(in: bounds, gaps: gaps)[ObjectIdentifier(targetLeaf)] ?? bounds
        let axis: Axis = rect.width >= rect.height ? .horizontal : .vertical
        let parent = targetLeaf.parent
        let wasFirst = parent?.first === targetLeaf
        let split = Node(axis: axis, ratio: 0.5, first: targetLeaf, second: newLeaf)
        replace(child: targetLeaf, of: parent, wasFirst: wasFirst, with: split)
    }

    @discardableResult
    public func remove(_ id: WindowID) -> Bool {
        guard let node = leaf(id) else { return false }
        guard let parent = node.parent else {
            root = nil
            return true
        }
        let sibling = (parent.first === node ? parent.second : parent.first)!
        replace(child: parent, of: parent.parent, wasFirst: parent.parent?.first === parent, with: sibling)
        return true
    }

    private func replace(child: Node, of parent: Node?, wasFirst: Bool, with replacement: Node) {
        replacement.parent = parent
        if let parent {
            if wasFirst { parent.first = replacement } else { parent.second = replacement }
        } else {
            root = replacement
        }
    }

    /// The window that would take over `id`'s space if it were removed. Used to put a window
    /// back where it was after it is minimized, hidden or returns from native fullscreen.
    public func sibling(of id: WindowID) -> WindowID? {
        guard let node = leaf(id), let parent = node.parent else { return nil }
        let other = parent.first === node ? parent.second : parent.first
        return other?.leaves.first?.window
    }

    public func swap(_ a: WindowID, _ b: WindowID) {
        guard let la = leaf(a), let lb = leaf(b) else { return }
        la.window = b
        lb.window = a
    }

    /// Flips the axis of the split that contains `id`.
    public func toggleSplit(_ id: WindowID) {
        guard let parent = leaf(id)?.parent else { return }
        parent.axis = parent.axis.flipped
    }

    /// Resets ratios so every window gets an equal share along each axis.
    public func balance() {
        func visit(_ node: Node?) -> Int {
            guard let node else { return 0 }
            if node.window != nil { return 1 }
            let a = visit(node.first)
            let b = visit(node.second)
            node.ratio = Double(a) / Double(a + b)
            return a + b
        }
        _ = visit(root)
    }

    /// Grows (positive `delta`) or shrinks the window along `axis` by `delta` points, by moving
    /// the nearest split on that axis.
    public func resize(_ id: WindowID, axis: Axis, by delta: Double, in bounds: CGRect, gaps: Gaps = .zero) {
        guard let node = leaf(id) else { return }
        var child = node
        var current = node.parent
        while let parent = current, parent.axis != axis {
            child = parent
            current = parent.parent
        }
        guard let parent = current, let rect = nodeRects(in: bounds, gaps: gaps)[ObjectIdentifier(parent)] else { return }
        let size = Double(axis == .horizontal ? rect.width : rect.height)
        guard size > 0 else { return }
        let change = delta / size
        parent.ratio = clamp(parent.ratio + (parent.first === child ? change : -change))
    }

    /// Updates split ratios so `id`'s computed frame matches `frame` as closely as the tree
    /// allows. Used when the user resizes a tiled window with the mouse.
    public func adjust(_ id: WindowID, toMatch frame: CGRect, in bounds: CGRect, gaps: Gaps = .zero) {
        guard let node = leaf(id) else { return }
        let rects = nodeRects(in: bounds, gaps: gaps)
        guard let current = rects[ObjectIdentifier(node)] else { return }
        let gap = CGFloat(gaps.inner)
        let tolerance: CGFloat = 2

        func ancestor(axis: Axis, childIsFirst: Bool) -> (Node, CGRect)? {
            var child = node
            var current = node.parent
            while let parent = current {
                if parent.axis == axis, (parent.first === child) == childIsFirst,
                   let rect = rects[ObjectIdentifier(parent)] {
                    return (parent, rect)
                }
                child = parent
                current = parent.parent
            }
            return nil
        }

        if abs(frame.minX - current.minX) > tolerance, let (p, r) = ancestor(axis: .horizontal, childIsFirst: false) {
            p.ratio = clamp(Double((frame.minX - gap - r.minX) / (r.width - gap)))
        }
        if abs(frame.maxX - current.maxX) > tolerance, let (p, r) = ancestor(axis: .horizontal, childIsFirst: true) {
            p.ratio = clamp(Double((frame.maxX - r.minX) / (r.width - gap)))
        }
        if abs(frame.minY - current.minY) > tolerance, let (p, r) = ancestor(axis: .vertical, childIsFirst: false) {
            p.ratio = clamp(Double((frame.minY - gap - r.minY) / (r.height - gap)))
        }
        if abs(frame.maxY - current.maxY) > tolerance, let (p, r) = ancestor(axis: .vertical, childIsFirst: true) {
            p.ratio = clamp(Double((frame.maxY - r.minY) / (r.height - gap)))
        }
    }

    private func clamp(_ ratio: Double) -> Double {
        min(max(ratio, Self.ratioRange.lowerBound), Self.ratioRange.upperBound)
    }

    // MARK: - Layout

    public func frames(in bounds: CGRect, gaps: Gaps = .zero) -> [WindowID: CGRect] {
        var out: [WindowID: CGRect] = [:]
        walk(in: bounds, gaps: gaps) { node, rect in
            if let window = node.window { out[window] = rect }
        }
        return out
    }

    private func nodeRects(in bounds: CGRect, gaps: Gaps) -> [ObjectIdentifier: CGRect] {
        var out: [ObjectIdentifier: CGRect] = [:]
        walk(in: bounds, gaps: gaps) { node, rect in out[ObjectIdentifier(node)] = rect }
        return out
    }

    private func walk(in bounds: CGRect, gaps: Gaps, _ body: (Node, CGRect) -> Void) {
        guard let root else { return }
        let outer = CGFloat(gaps.outer)
        visit(root, bounds.insetBy(dx: outer, dy: outer), gap: CGFloat(gaps.inner), body)
    }

    private func visit(_ node: Node, _ rect: CGRect, gap: CGFloat, _ body: (Node, CGRect) -> Void) {
        body(node, rect)
        guard let first = node.first, let second = node.second else { return }
        let (a, b) = Self.split(rect, axis: node.axis, ratio: node.ratio, gap: gap)
        visit(first, a, gap: gap, body)
        visit(second, b, gap: gap, body)
    }

    static func split(_ rect: CGRect, axis: Axis, ratio: Double, gap: CGFloat) -> (CGRect, CGRect) {
        switch axis {
        case .horizontal:
            let available = max(rect.width - gap, 0)
            let w = available * CGFloat(ratio)
            return (
                CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height),
                CGRect(x: rect.minX + w + gap, y: rect.minY, width: available - w, height: rect.height)
            )
        case .vertical:
            let available = max(rect.height - gap, 0)
            let h = available * CGFloat(ratio)
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h),
                CGRect(x: rect.minX, y: rect.minY + h + gap, width: rect.width, height: available - h)
            )
        }
    }
}
