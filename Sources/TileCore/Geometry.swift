import CoreGraphics

/// A CoreGraphics window number (`CGWindowID`). Stable for the lifetime of a window and
/// shared between the Accessibility API and SkyLight, so it is our window identity.
public typealias WindowID = UInt32

/// All TileCore geometry uses the Accessibility / CoreGraphics global coordinate space:
/// origin at the top-left of the primary display, y growing downward.
public enum Direction: String, CaseIterable, Sendable {
    case left, right, up, down

    public var axis: Axis { (self == .left || self == .right) ? .horizontal : .vertical }
    /// Right and down move toward the `second` child of a split.
    public var isForward: Bool { self == .right || self == .down }
}

public enum Axis: String, Sendable {
    /// Children laid out side by side.
    case horizontal
    /// Children stacked top to bottom.
    case vertical

    public var flipped: Axis { self == .horizontal ? .vertical : .horizontal }
}

public struct Gaps: Codable, Equatable, Sendable {
    public var inner: Double
    public var outer: Double

    public init(inner: Double = 0, outer: Double = 0) {
        self.inner = inner
        self.outer = outer
    }

    public static let zero = Gaps()
}

public enum Geometry {
    /// Picks the candidate that lies in `direction` from `source`, preferring candidates that
    /// overlap `source` on the perpendicular axis, then the nearest, then the best aligned.
    /// Works across displays because displays share one global coordinate space.
    public static func closest<ID>(
        from source: CGRect,
        toward direction: Direction,
        among candidates: [(ID, CGRect)],
        tolerance: CGFloat = 16
    ) -> ID? {
        var best: (id: ID, score: CGFloat, alignment: CGFloat)?
        for (id, rect) in candidates {
            let distance: CGFloat
            let overlap: CGFloat
            let alignment: CGFloat
            switch direction {
            case .left:
                guard rect.maxX <= source.minX + tolerance, rect.midX < source.midX else { continue }
                distance = source.minX - rect.maxX
                overlap = min(rect.maxY, source.maxY) - max(rect.minY, source.minY)
                alignment = abs(rect.midY - source.midY)
            case .right:
                guard rect.minX >= source.maxX - tolerance, rect.midX > source.midX else { continue }
                distance = rect.minX - source.maxX
                overlap = min(rect.maxY, source.maxY) - max(rect.minY, source.minY)
                alignment = abs(rect.midY - source.midY)
            case .up:
                guard rect.maxY <= source.minY + tolerance, rect.midY < source.midY else { continue }
                distance = source.minY - rect.maxY
                overlap = min(rect.maxX, source.maxX) - max(rect.minX, source.minX)
                alignment = abs(rect.midX - source.midX)
            case .down:
                guard rect.minY >= source.maxY - tolerance, rect.midY > source.midY else { continue }
                distance = rect.minY - source.maxY
                overlap = min(rect.maxX, source.maxX) - max(rect.minX, source.minX)
                alignment = abs(rect.midX - source.midX)
            }
            let score = max(distance, 0) + (overlap > 0 ? 0 : 100_000 - overlap)
            if let current = best {
                if score < current.score - 0.5 || (abs(score - current.score) <= 0.5 && alignment < current.alignment) {
                    best = (id, score, alignment)
                }
            } else {
                best = (id, score, alignment)
            }
        }
        return best?.id
    }

    public static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// Converts between Cocoa (bottom-left origin) and AX (top-left origin) rects.
    /// The conversion is its own inverse.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1.5) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

extension CGRect {
    /// Snaps to whole points so we never ask a window for a fractional frame.
    public var pixelAligned: CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }
}
