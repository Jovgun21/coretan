import Foundation

// Little-endian primitives for compact ink storage.
extension Data {
    mutating func appendMagic(_ s: String) { append(contentsOf: Array(s.utf8)) }
    mutating func append<T: FixedWidthInteger>(_ v: T) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func append(_ v: UUID) {
        var u = v.uuid
        Swift.withUnsafeBytes(of: &u) { append(contentsOf: $0) }
    }
}

final class ByteReader {
    enum ReadError: Error { case outOfData, badMagic }

    private let d: Data
    private var o: Int = 0

    init(_ data: Data) { d = data }

    func bytes(_ n: Int) -> Data? {
        guard n >= 0, o + n <= d.count else { return nil }
        defer { o += n }
        return d[o..<o + n]
    }

    func magic(_ s: String) throws {
        guard let b = bytes(s.utf8.count), Array(b) == Array(s.utf8) else { throw ReadError.badMagic }
    }

    func u16() -> UInt16? {
        guard let b = bytes(2) else { return nil }
        return b.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian }
    }

    func u32() -> UInt32? {
        guard let b = bytes(4) else { return nil }
        return b.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    }

    func f32() -> Float? {
        guard let v = u32() else { return nil }
        return Float(bitPattern: v)
    }

    func uuid() -> UUID? {
        guard let b = bytes(16) else { return nil }
        return b.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    /// Reads u32 length + bytes and decodes it as JSON. `nil` on any read or
    /// decode failure, so callers can bail out with a single guard.
    func json<T: Decodable>(_ type: T.Type) -> T? {
        guard let n = u32(), n != UInt32.max, let b = bytes(Int(n)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: b)
    }
}