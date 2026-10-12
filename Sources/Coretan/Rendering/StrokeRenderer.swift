import UIKit

/// Draws ink strokes into any CGContext. Shared by the live canvas, thumbnails
/// and PDF export so a stroke looks identical in all three.
enum StrokeRenderer {

    static func draw(_ strokes: [InkStroke], in ctx: CGContext, layers: [InkLayer]) {
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for group in grouped(strokes, layers: layers) {
            for s in group {
                drawOne(s, in: ctx)
            }
        }
    }

    private static func grouped(_ strokes: [InkStroke], layers: [InkLayer]) -> [[InkStroke]] {
        guard !layers.isEmpty else { return [strokes] }
        return layers.sorted { $0.zIndex < $1.zIndex }
            .filter { $0.isVisible }
            .map { l in strokes.filter { $0.layerID == l.id } }
    }

    static func drawOne(_ s: InkStroke, in ctx: CGContext) {
        let alpha: CGFloat = s.tool == .highlighter ? 0.35 : 1.0
        ctx.setStrokeColor(s.color.ui.withAlphaComponent(alpha).cgColor)
        ctx.setFillColor(s.color.ui.withAlphaComponent(alpha).cgColor)

        if let shape = s.shape {
            drawShape(shape, stroke: s, in: ctx)
            return
        }
        let pts = s.points
        guard pts.count > 1 else {
            guard let p = pts.first else { return }
            let w = CGFloat(s.width(at: p))
            ctx.fillEllipse(in: CGRect(x: p.cg.x - w/2, y: p.cg.y - w/2, width: w, height: w))
            return
        }
        for i in 1..<pts.count {
            let a = pts[i-1], b = pts[i]
            ctx.setLineWidth(CGFloat(s.width(at: b)))
            ctx.move(to: a.cg); ctx.addLine(to: b.cg); ctx.strokePath()
        }
    }

    static func drawShape(_ shape: InkShape, stroke s: InkStroke, in ctx: CGContext) {
        ctx.setLineWidth(CGFloat(s.baseWidth))
        let r = CGRect(x: min(shape.a.x, shape.b.x), y: min(shape.a.y, shape.b.y),
                       width: abs(shape.b.x - shape.a.x), height: abs(shape.b.y - shape.a.y))
        switch shape.kind {
        case .line:
            ctx.move(to: shape.a); ctx.addLine(to: shape.b); ctx.strokePath()
        case .arrow:
            ctx.move(to: shape.a); ctx.addLine(to: shape.b); ctx.strokePath()
            let angle = atan2(shape.b.y - shape.a.y, shape.b.x - shape.a.x)
            let len: CGFloat = max(10, CGFloat(s.baseWidth) * 4)
            for delta in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
                ctx.move(to: shape.b)
                ctx.addLine(to: CGPoint(x: shape.b.x + len * cos(angle + delta),
                                        y: shape.b.y + len * sin(angle + delta)))
            }
            ctx.strokePath()
        case .rect:
            ctx.stroke(r)
        case .ellipse:
            ctx.strokeEllipse(in: r)
        case .triangle:
            ctx.move(to: CGPoint(x: r.midX, y: r.minY))
            ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            ctx.closePath(); ctx.strokePath()
        case .diamond:
            ctx.move(to: CGPoint(x: r.midX, y: r.minY))
            ctx.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            ctx.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            ctx.addLine(to: CGPoint(x: r.minX, y: r.midY))
            ctx.closePath(); ctx.strokePath()
        }
    }
}
