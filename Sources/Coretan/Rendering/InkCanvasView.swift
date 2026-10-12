import UIKit

protocol InkCanvasDelegate: AnyObject {
    func canvas(_ c: InkCanvasView, didFinish stroke: InkStroke, onPage pageID: UUID)
    func canvas(_ c: InkCanvasView, didErase strokes: [UUID], onPage pageID: UUID)
    func canvas(_ c: InkCanvasView, didTransform ids: [UUID], from: [CGPoint], to: [CGPoint])
    func canvasDidChangeSelection(_ c: InkCanvasView, ids: [UUID])
}

enum EditorTool {
    case pen(InkToolKind, InkColor, Float)
    case eraser(Float, EraserTarget)
    case lasso
    case move
    enum EraserTarget { case any, inkOnly, highlighterOnly }
}

/// Core drawing surface. Renders paper + ink with CoreGraphics, keeps every
/// stroke vector so zoom stays sharp and edits stay lossless.
final class InkCanvasView: UIView {

    weak var delegate: InkCanvasDelegate?

    var tool: EditorTool = .pen(.pen, InkColor(r: 0.1, g: 0.1, b: 0.1, a: 1), 3)
    var pageSize: PageSize = .a4Portrait { didSet { setNeedsDisplay() } }
    var template: TemplateSpec = .ruled { didSet { paperImage = nil; setNeedsDisplay() } }
    var layers: [InkLayer] = [InkLayer(id: UUID(), name: "Tinta", isVisible: true, isLocked: false, zIndex: 0)]

    /// Page zoom/pan is owned by the enclosing scroll view; this view works in page space.
    private(set) var strokes: [InkStroke] = []
    private(set) var selection: Set<UUID> = []

    private var paperImage: UIImage?
    private var liveStroke: InkStroke?
    private var lastPoint: InkPoint?
    private var strokeStart: CFAbsoluteTime = 0
    private var selectionOrigin: CGPoint = .zero
    private var transformStart: [UUID: [CGPoint]] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .white
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: Data

    func load(strokes: [InkStroke]) {
        self.strokes = strokes
        selection.removeAll()
        setNeedsDisplay()
    }

    func currentStrokes() -> [InkStroke] { strokes }

    // MARK: Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = point(from: t)
        strokeStart = CFAbsoluteTimeGetCurrent()

        switch tool {
        case .pen(let kind, let color, let width):
            let layerID = layers.first(where: { $0.isVisible && !$0.isLocked })?.id ?? UUID()
            liveStroke = InkStroke(id: UUID(), tool: kind, color: color, baseWidth: width,
                                   layerID: layerID, points: [p], shape: nil)
            lastPoint = p
            setNeedsDisplay()
        case .eraser:
            erase(at: p)
        case .lasso:
            selectionOrigin = p
            selection.removeAll()
            delegate?.canvasDidChangeSelection(self, ids: [])
        case .move:
            selectionOrigin = p
            transformStart = Dictionary(uniqueKeysWithValues:
                strokes.filter { selection.contains($0.id) }
                       .map { ($0.id, $0.points.map(\.cg)) })
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = point(from: t)

        switch tool {
        case .pen:
            guard var s = liveStroke else { return }
            // coalesced touches keep fast Apple Pencil input smooth
            let coalesced = (event?.coalescedTouches(for: t) ?? [t]).map { point(from: $0) }
            s.points.append(contentsOf: coalesced)
            liveStroke = s
            lastPoint = p
            setNeedsDisplay(rect(s.bounds).insetBy(dx: -8, dy: -8))
        case .eraser:
            erase(at: p)
        case .lasso:
            lassoUpdate(to: p)
        case .move:
            moveSelection(by: CGPoint(x: p.x - selectionOrigin.x, y: p.y - selectionOrigin.y))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = point(from: t)
        switch tool {
        case .pen:
            guard var s = liveStroke else { return }
            s.points.append(p)
            liveStroke = nil
            guard s.points.count > 1 else { setNeedsDisplay(); return }
            // shape snapping only when the user drew slowly and deliberately
            if let snapped = snapIfDeliberate(s) { s = snapped }
            strokes.append(s)
            delegate?.canvas(self, didFinish: s, onPage: currentPageID)
            setNeedsDisplay()
        case .lasso:
            finalizeLasso()
        case .move:
            let ids = Array(selection)
            let froms = ids.compactMap { transformStart[$0] }
            let tos = ids.compactMap { id in strokes.first(where: { $0.id == id })?.points.map(\.cg) }
            if !ids.isEmpty { delegate?.canvas(self, didTransform: ids, from: froms.flatMap { $0 }, to: tos.flatMap { $0 }) }
            transformStart.removeAll()
        case .eraser:
            break
        }
        lastPoint = nil
    }

    // MARK: Geometry

    var currentPageID: UUID = UUID()

    private func point(from touch: UITouch) -> InkPoint {
        let loc = touch.preciseLocation(in: self)
        let force = touch.force > 0 ? Float(touch.force / max(touch.maximumPossibleForce, 1)) : 0
        let alt = touch.type == .pencil ? Float(touch.altitudeAngle) : Float.pi / 2
        let az = touch.type == .pencil ? Float(touch.azimuthAngle(in: self)) : 0
        let dt = Int32(max(0, (CFAbsoluteTimeGetCurrent() - strokeStart) * 1000))
        return InkPoint(x: Float(loc.x), y: Float(loc.y), force: force,
                        altitude: alt, azimuth: az, tOffset: dt)
    }

    private func rect(_ r: CGRect) -> CGRect { r }

    // MARK: Snapping

    private func snapIfDeliberate(_ s: InkStroke) -> InkStroke? {
        guard s.tool != .highlighter else { return nil }
        let dur = s.points.last?.tOffset ?? 0
        guard dur > 120 else { return nil }          // too fast to be an intentional shape
        guard let r = ShapeRecognizer.recognize(points: s.points) else { return nil }
        let promoted = ShapeRecognizer.arrowIfPossible(r, points: s.points)
        guard promoted.confidence > 0.6 else { return nil }
        var out = s
        out.shape = InkShape(kind: promoted.kind, a: promoted.a, b: promoted.b)
        return out
    }

    // MARK: Erase

    private func erase(at p: InkPoint) {
        guard case .eraser(let radius, let target) = tool else { return }
        let pt = p.cg
        let r = CGFloat(radius)
        var removed: [UUID] = []
        strokes.removeAll { s in
            guard shouldErase(s, target: target) else { return false }
            guard s.bounds.insetBy(dx: -r, dy: -r).contains(pt) else { return false }
            let hit = s.points.contains { hypot($0.cg.x - pt.x, $0.cg.y - pt.y) <= r + CGFloat(s.baseWidth) }
            if hit { removed.append(s.id) }
            return hit
        }
        if !removed.isEmpty {
            delegate?.canvas(self, didErase: removed, onPage: currentPageID)
            setNeedsDisplay()
        }
    }

    private func shouldErase(_ s: InkStroke, target: EditorTool.EraserTarget) -> Bool {
        switch target {
        case .any: return true
        case .inkOnly: return s.tool != .highlighter
        case .highlighterOnly: return s.tool == .highlighter
        }
    }

    // MARK: Lasso

    private var lassoPath: [CGPoint] = []
    private var lassoPolygon: [CGPoint] = []

    private func lassoUpdate(to p: InkPoint) {
        lassoPath.append(p.cg)
        setNeedsDisplay()
    }

    private func finalizeLasso() {
        lassoPolygon = lassoPath
        lassoPath = []
        guard lassoPolygon.count > 3 else { setNeedsDisplay(); return }
        var hits: Set<UUID> = []
        for s in strokes {
            if s.points.contains(where: { pointInPolygon($0.cg, lassoPolygon) })
                || pointInPolygon(s.bounds.origin, lassoPolygon) {
                hits.insert(s.id)
            }
        }
        selection = hits
        delegate?.canvasDidChangeSelection(self, ids: Array(hits))
        setNeedsDisplay()
    }

    private func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if ((a.y > p.y) != (b.y > p.y)) &&
                (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func moveSelection(by delta: CGPoint) {
        guard !selection.isEmpty else { return }
        for i in strokes.indices where selection.contains(strokes[i].id) {
            guard let orig = transformStart[strokes[i].id] else { continue }
            for k in strokes[i].points.indices where k < orig.count {
                strokes[i].points[k].x = Float(orig[k].x + delta.x)
                strokes[i].points[k].y = Float(orig[k].y + delta.y)
            }
        }
        setNeedsDisplay()
    }

    // MARK: Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let size = pageSize.cg
        if paperImage == nil { paperImage = TemplateRenderer.image(for: template, size: size) }
        paperImage?.draw(at: .zero)

        for layer in layers.sorted(by: { $0.zIndex < $1.zIndex }) where layer.isVisible {
            for s in strokes where s.layerID == layer.id {
                draw(s, in: ctx)
            }
        }
        // live stroke on top
        if let live = liveStroke { draw(live, in: ctx) }

        if !lassoPath.isEmpty {
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.addLines(between: lassoPath)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        if !selection.isEmpty {
            ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1.5)
            for s in strokes where selection.contains(s.id) {
                ctx.stroke(s.bounds)
            }
        }
    }

    private func draw(_ s: InkStroke, in ctx: CGContext) {
        let alpha: CGFloat = s.tool == .highlighter ? 0.35 : 1.0
        ctx.setStrokeColor(s.color.ui.withAlphaComponent(alpha).cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if let shape = s.shape {
            drawShape(shape, s: s, in: ctx)
            return
        }

        // variable-width stroke: segment by segment so pressure reads correctly
        let pts = s.points
        guard pts.count > 1 else {
            let p = pts.first?.cg ?? .zero
            ctx.setFillColor(s.color.ui.withAlphaComponent(alpha).cgColor)
            let w = CGFloat(s.width(at: pts.first ?? InkPoint(x: 0, y: 0, force: 1, altitude: 1.57, azimuth: 0, tOffset: 0)))
            ctx.fillEllipse(in: CGRect(x: p.x - w/2, y: p.y - w/2, width: w, height: w))
            return
        }
        for i in 1..<pts.count {
            let a = pts[i-1], b = pts[i]
            ctx.setLineWidth(CGFloat(s.width(at: b)))
            ctx.move(to: a.cg); ctx.addLine(to: b.cg); ctx.strokePath()
        }
    }

    private func drawShape(_ shape: InkShape, s: InkStroke, in ctx: CGContext) {
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

    /// Rasterised snapshot used for thumbnails.
    func snapshot(scale: CGFloat = 0.25) -> UIImage {
        let size = pageSize.cg
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let r = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale), format: fmt)
        return r.image { c in
            c.cgContext.scaleBy(x: scale, y: scale)
            (paperImage ?? TemplateRenderer.image(for: template, size: size)).draw(at: .zero)
            for layer in layers.sorted(by: { $0.zIndex < $1.zIndex }) where layer.isVisible {
                for s in strokes where s.layerID == layer.id { draw(s, in: c.cgContext) }
            }
        }
    }
}
