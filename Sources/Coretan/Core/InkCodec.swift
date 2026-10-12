import Foundation

/// Compact binary container for ink layers:
/// magic "CTNK" | u16 version | u32 pageCount | per page { ... }.
///
/// Chosen over JSON because a notebook with tens of thousands of strokes has to
/// load in well under a second and stay small on disk. Every variable-length
/// field is written as u32 length + bytes, so a reader can always skip forward.
enum InkCodec {
    static let version: UInt16 = 1

    struct PagePayload {
        var pageID: UUID
        var size: PageSize
        var template: TemplateSpec
        var backgroundAsset: String?
        var layers: [InkLayer]
        var strokes: [InkStroke]
        var media: [MediaObject]
    }

    // MARK: Encode

    static func encode(pages: [PagePayload]) -> Data {
        var out = Data()
        out.appendMagic("CTNK")
        out.append(version)
        out.append(UInt32(pages.count))
        for p in pages {
            out.append(p.pageID)
            out.append(p.size.width)
            out.append(p.size.height)
            appendBlob(try? JSONEncoder().encode(p.template), to: &out)
            if let bg = p.backgroundAsset, let d = bg.data(using: .utf8) {
                appendBlob(d, to: &out)
            } else {
                out.append(UInt32.max)   // null marker
            }
            out.append(UInt32(p.layers.count))
            for l in p.layers { appendBlob(try? JSONEncoder().encode(l), to: &out) }
            out.append(UInt32(p.strokes.count))
            for s in p.strokes { appendBlob(try? JSONEncoder().encode(s), to: &out) }
            out.append(UInt32(p.media.count))
            for m in p.media { appendBlob(try? JSONEncoder().encode(m), to: &out) }
        }
        return out
    }

    private static func appendBlob(_ data: Data?, to out: inout Data) {
        guard let data else { out.append(UInt32.max); return }
        out.append(UInt32(data.count))
        out.append(data)
    }

    // MARK: Decode

    static func decode(_ data: Data) -> [PagePayload]? {
        let r = ByteReader(data)
        do { try r.magic("CTNK") } catch { return nil }
        guard let v = r.u16(), v == version, let count = r.u32() else { return nil }

        var pages: [PagePayload] = []
        pages.reserveCapacity(Int(count))

        for _ in 0..<count {
            guard let pageID = r.uuid(),
                  let w = r.f32(),
                  let h = r.f32(),
                  let tpl = r.json(TemplateSpec.self),
                  let bgLen = r.u32()
            else { return nil }

            var background: String?
            if bgLen != UInt32.max {
                guard let d = r.bytes(Int(bgLen)) else { return nil }
                background = String(data: d, encoding: .utf8)
            }

            guard let lc = r.u32() else { return nil }
            var layers: [InkLayer] = []
            layers.reserveCapacity(Int(lc))
            for _ in 0..<lc {
                guard let l = r.json(InkLayer.self) else { return nil }
                layers.append(l)
            }

            guard let sc = r.u32() else { return nil }
            var strokes: [InkStroke] = []
            strokes.reserveCapacity(Int(sc))
            for _ in 0..<sc {
                guard let s = r.json(InkStroke.self) else { return nil }
                strokes.append(s)
            }

            guard let mc = r.u32() else { return nil }
            var media: [MediaObject] = []
            media.reserveCapacity(Int(mc))
            for _ in 0..<mc {
                guard let m = r.json(MediaObject.self) else { return nil }
                media.append(m)
            }

            pages.append(PagePayload(pageID: pageID,
                                     size: PageSize(width: w, height: h),
                                     template: tpl,
                                     backgroundAsset: background,
                                     layers: layers,
                                     strokes: strokes,
                                     media: media))
        }
        return pages
    }
}