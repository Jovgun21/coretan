import Foundation

struct InkLayer: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var isVisible: Bool
    var isLocked: Bool
    var zIndex: Int32
}

struct MediaObject: Codable, Equatable {
    var id: UUID
    var kind: Int16 // 0 image, 1 textBox, 2 sticker
    var frame: CGRectCodable
    var assetName: String // relative to notebook bundle
    var z: Int32
    var rotation: Float
}

struct CGRectCodable: Codable, Equatable {
    var x: Float; var y: Float; var w: Float; var h: Float
    var cg: CGRect { CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h)) }
    init(_ r: CGRect) { x = Float(r.origin.x); y = Float(r.origin.y); w = Float(r.size.width); h = Float(r.size.height) }
}
