import CoreGraphics
import Foundation

/// Geometric shape snapping. Runs on a finished stroke; returns a parametric
/// shape only when the fit is good, so scribbled notes never get mangled.
enum ShapeRecognizer {

    struct Result {
        var kind: InkShape.Kind
        var a: CGPoint
        var b: CGPoint
        var confidence: CGFloat
    }

    static func recognize(points: [InkPoint]) -> Result? {
        let pts = points.map(\.cg)
        guard pts.count >= 4 else { return nil }

        let xs = pts.map(\.x), ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX, h = maxY - minY
        guard w > 6 || h > 6 else { return nil }
        let a = CGPoint(x: minX, y: minY), b = CGPoint(x: maxX, y: maxY)

        // closed-ness: how far the ends are from each other relative to size
        let closedness = distance(pts.first!, pts.last!) / max(w, h, 1)

        // straightness: max perpendicular deviation from the chord
        if let dev = maxChordDeviation(pts), dev / max(w, h, 1) < 0.06 {
            return Result(kind: .line, a: pts.first!, b: pts.last!, confidence: 1 - dev / max(w, h, 1))
        }

        guard closedness < 0.35 else { return nil }

        // circularity via radial variance around the centroid
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let radii = pts.map { distance($0, CGPoint(x: cx, y: cy)) }
        let meanR = radii.reduce(0, +) / CGFloat(radii.count)
        let variance = radii.reduce(0) { $0 + ($1 - meanR) * ($1 - meanR) } / CGFloat(radii.count)
        let cv = sqrt(variance) / max(meanR, 1)

        let aspect = w / max(h, 0.001)
        if cv < 0.12 {
            if aspect > 0.8 && aspect < 1.25 {
                return Result(kind: .ellipse, a: a, b: b, confidence: 1 - cv)
            }
            return Result(kind: .ellipse, a: a, b: b, confidence: 1 - cv)
        }

        // corner count for polygon-ish shapes
        let corners = countCorners(pts)
        if corners == 3 { return Result(kind: .triangle, a: a, b: b, confidence: 0.8) }
        if corners == 4 {
            let fillRatio = polygonArea(pts) / max(w * h, 1)
            if fillRatio > 0.9 { return Result(kind: .rect, a: a, b: b, confidence: 0.85) }
            return Result(kind: .diamond, a: a, b: b, confidence: 0.7)
        }
        if fillRatioLikeRect(pts, a: a, b: b) > 0.9 {
            return Result(kind: .rect, a: a, b: b, confidence: 0.75)
        }
        return nil
    }

    /// Promotes a polyline into an arrow when the head is much shorter than the shaft.
    static func arrowIfPossible(_ r: Result, points: [InkPoint]) -> Result {
        guard r.kind == .line else { return r }
        let pts = points.map(\.cg)
        guard pts.count > 6 else { return r }
        let total = polylineLength(pts)
        let straight = distance(pts.first!, pts.last!)
        // a hook at the end makes the drawn length noticeably longer than the chord
        if total > straight * 1.12 { return Result(kind: .arrow, a: pts.first!, b: pts.last!, confidence: r.confidence) }
        return r
    }

    // MARK: helpers

    private static func distance(_ p: CGPoint, _ q: CGPoint) -> CGFloat {
        hypot(p.x - q.x, p.y - q.y)
    }

    private static func polylineLength(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        var l: CGFloat = 0
        for i in 1..<pts.count { l += distance(pts[i-1], pts[i]) }
        return l
    }

    private static func maxChordDeviation(_ pts: [CGPoint]) -> CGFloat? {
        guard let first = pts.first, let last = pts.last, first != last else { return nil }
        let dx = last.x - first.x, dy = last.y - first.y
        let len = hypot(dx, dy)
        guard len > 0 else { return nil }
        var maxDev: CGFloat = 0
        for p in pts {
            let dev = abs(dy * (p.x - first.x) - dx * (p.y - first.y)) / len
            if dev > maxDev { maxDev = dev }
        }
        return maxDev
    }

    private static func countCorners(_ pts: [CGPoint]) -> Int {
        guard pts.count > 6 else { return 0 }
        let step = max(1, pts.count / 40)
        var simplified: [CGPoint] = []
        var i = 0
        while i < pts.count { simplified.append(pts[i]); i += step }
        var corners = 0
        let k = 2
        for i in k..<(simplified.count - k) {
            let prev = simplified[i - k], cur = simplified[i], next = simplified[i + k]
            let v1 = CGPoint(x: cur.x - prev.x, y: cur.y - prev.y)
            let v2 = CGPoint(x: next.x - cur.x, y: next.y - cur.y)
            let n1 = hypot(v1.x, v1.y), n2 = hypot(v2.x, v2.y)
            guard n1 > 0, n2 > 0 else { continue }
            let cosT = (v1.x * v2.x + v1.y * v2.y) / (n1 * n2)
            if cosT < 0.35 { corners += 1 }   // sharp enough turn to be a corner
        }
        return corners
    }

    private static func polygonArea(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 2 else { return 0 }
        var area: CGFloat = 0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            area += pts[i].x * pts[j].y - pts[j].x * pts[i].y
        }
        return abs(area) / 2
    }

    private static func fillRatioLikeRect(_ pts: [CGPoint], a: CGPoint, b: CGPoint) -> CGFloat {
        polygonArea(pts) / max((b.x - a.x) * (b.y - a.y), 1)
    }
}
