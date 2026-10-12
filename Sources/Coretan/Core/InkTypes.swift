import UIKit

/// Tool kinds supported by the ink engine.
enum InkToolKind: Int16, Codable, CaseIterable {
    case pen = 0
    case highlighter = 1
    case pencil = 2
}

/// A single sampled input point. Coordinates are stored in page space (points),
/// origin top-left, independent of zoom.
struct InkPoint: Codable, Equatable {
    var x: Float
    var y: Float
    /// Normalized force 0...1 (1 when the device reports no pressure).
    var force: Float
    /// Pencil altitude in radians; .pi/2 means fully vertical.
    var altitude: Float
    /// Pencil azimuth in radians.
    var azimuth: Float
    /// Milliseconds since stroke start. Drives Note Replay ordering.
    var tOffset: Int32

    var cg: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
}

/// Color stored as RGBA components 0...1 so it survives re-encoding exactly.
struct InkColor: Codable, Equatable {
    var r: Float
    var g: Float
    var b: Float
    var a: Float

    var ui: UIColor {
        UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    static func from(_ color: UIColor) -> InkColor {
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 1
        color.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        return InkColor(r: Float(rr), g: Float(gg), b: Float(bb), a: Float(aa))
    }
}

/// Parametric shapes keep diagram editing lossless after flattening.
struct InkShape: Codable, Equatable {
    enum Kind: Int16, Codable { case line, arrow, rect, ellipse, triangle, diamond }
    var kind: Kind
    var a: CGPoint
    var b: CGPoint
}

/// One continuous pen stroke. Editable after the fact: color, width and points
/// are all retained, never baked into a bitmap.
struct InkStroke: Codable, Equatable {
    var id: UUID
    var tool: InkToolKind
    var color: InkColor
    /// Base width in page points at full pressure.
    var baseWidth: Float
    var layerID: UUID
    var points: [InkPoint]
    /// Non-nil when the stroke was flattened into a parametric shape.
    var shape: InkShape?

    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        var wMax: Float = baseWidth
        for p in points {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
            let w = width(at: p)
            if w > wMax { wMax = w }
        }
        let pad = CGFloat(wMax) / 2.0 + 1.0
        return CGRect(x: CGFloat(minX) - pad, y: CGFloat(minY) - pad,
                      width: CGFloat(maxX - minX) + pad * 2,
                      height: CGFloat(maxY - minY) + pad * 2)
    }

    /// Pressure- and tilt-responsive width for a point.
    func width(at p: InkPoint) -> Float {
        let press = max(0.12, min(1.0, p.force > 0 ? p.force : 0.85))
        var w: Float
        switch tool {
        case .highlighter:
            w = baseWidth
        case .pen:
            w = baseWidth * (0.35 + 0.65 * press)
        case .pencil:
            let alt = max(0.05, min(Float.pi / 2, p.altitude > 0 ? p.altitude : Float.pi / 2))
            w = baseWidth * (0.35 + 0.65 * press) * ((Float.pi / 2) / alt)
        }
        return max(0.35, w)
    }
}

/// Page geometry, in points (72 dpi reference scale).
struct PageSize: Codable, Equatable {
    var width: Float
    var height: Float
    var cg: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }

    static let a4Portrait = PageSize(width: 595, height: 842)
    static let a4Landscape = PageSize(width: 842, height: 595)
    static let letterPortrait = PageSize(width: 612, height: 792)
    static let ipadProportional = PageSize(width: 834, height: 1112)

    var rotated: PageSize { PageSize(width: height, height: width) }
}
