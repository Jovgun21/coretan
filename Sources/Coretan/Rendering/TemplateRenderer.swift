import UIKit

/// Draws paper templates. Rendered into a cached image per page so the canvas
/// only ever composites: paper image + ink layer.
enum TemplateRenderer {

    static func image(for template: TemplateSpec, size: CGSize, scale: CGFloat = 2) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = scale
            f.opaque = true
            return f
        }())
        return renderer.image { ctx in
            let c = ctx.cgContext
            let paper = UIColor(hex: template.paperColorHex) ?? .white
            c.setFillColor(paper.cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            let line = UIColor.black.withAlphaComponent(0.16).cgColor
            c.setStrokeColor(line)
            c.setLineWidth(0.7)

            switch template.kind {
            case .blank:
                break
            case .ruled, .wideRuled, .narrowRuled, .studyNotes, .meetingNotes, .cornell:
                let spacing = CGFloat(template.lineSpacing ?? 24)
                horizontalLines(c, size: size, spacing: spacing)
                if template.kind == .cornell { cornell(c, size: size) }
            case .grid, .graph:
                let g = CGFloat(template.gridSize ?? 20)
                grid(c, size: size, step: g)
            case .dotGrid:
                dots(c, size: size, step: CGFloat(template.gridSize ?? 20))
            case .music:
                music(c, size: size)
            case .plannerDaily, .plannerWeekly, .plannerMonthly, .habitTracker, .todoList, .table:
                planner(c, size: size, kind: template.kind)
            case .math, .calculus, .statistics:
                grid(c, size: size, step: 28)
                horizontalLines(c, size: size, spacing: 28)
            case .diagram:
                dots(c, size: size, step: 24)
            case .custom:
                break
            }
        }
    }

    private static func horizontalLines(_ c: CGContext, size: CGSize, spacing: CGFloat) {
        var y = spacing
        while y < size.height {
            c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        c.strokePath()
    }

    private static func grid(_ c: CGContext, size: CGSize, step: CGFloat) {
        var x = step
        while x < size.width { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: size.height)); x += step }
        var y = step
        while y < size.height { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: size.width, y: y)); y += step }
        c.strokePath()
    }

    private static func dots(_ c: CGContext, size: CGSize, step: CGFloat) {
        c.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
        var y = step
        while y < size.height {
            var x = step
            while x < size.width {
                c.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                x += step
            }
            y += step
        }
    }

    private static func music(_ c: CGContext, size: CGSize) {
        let staffHeight: CGFloat = 40
        var top: CGFloat = 20
        while top + staffHeight < size.height {
            for i in 0..<5 {
                let y = top + CGFloat(i) * (staffHeight / 4)
                c.move(to: CGPoint(x: 24, y: y)); c.addLine(to: CGPoint(x: size.width - 24, y: y))
            }
            top += staffHeight + 24
        }
        c.strokePath()
    }

    private static func cornell(_ c: CGContext, size: CGSize) {
        let cueX = size.width * 0.32
        let summaryY = size.height * 0.78
        c.move(to: CGPoint(x: cueX, y: 0)); c.addLine(to: CGPoint(x: cueX, y: summaryY))
        c.move(to: CGPoint(x: 0, y: summaryY)); c.addLine(to: CGPoint(x: size.width, y: summaryY))
        c.strokePath()
    }

    private static func planner(_ c: CGContext, size: CGSize, kind: TemplateKind) {
        let columns = kind == .plannerWeekly ? 7 : (kind == .plannerMonthly ? 7 : 1)
        let rows = kind == .plannerMonthly ? 5 : (kind == .plannerDaily ? 6 : 1)
        let cw = size.width / CGFloat(columns), rh = size.height / CGFloat(rows + 1)
        for i in 1..<max(columns, 2) {
            let x = CGFloat(i) * cw
            c.move(to: CGPoint(x: x, y: rh)); c.addLine(to: CGPoint(x: x, y: size.height))
        }
        for j in 1...rows {
            let y = rh + CGFloat(j - 1) * (size.height - rh) / CGFloat(rows)
            c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: size.width, y: y))
        }
        c.strokePath()
    }
}

extension UIColor {
    /// "#RRGGBB" or "#RRGGBBAA".
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((v >> 24) & 0xFF) / 255
            g = CGFloat((v >> 16) & 0xFF) / 255
            b = CGFloat((v >> 8) & 0xFF) / 255
            a = CGFloat(v & 0xFF) / 255
        } else if s.count == 6 {
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255
            a = 1
        } else { return nil }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
