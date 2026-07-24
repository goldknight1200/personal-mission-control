import Foundation

public struct StableIdentifierGenerator: IdentifierGenerating, Sendable {
    public init() {}

    public func identifier(namespace: String) -> EntityID {
        let bytes = Array(namespace.utf8)
        let first = fnv1a64(bytes, seed: 14_695_981_039_346_656_037)
        let second = fnv1a64(
            bytes.reversed(),
            seed: 10_995_116_282_11
        )
        let tuple: uuid_t = (
            UInt8(truncatingIfNeeded: first >> 56),
            UInt8(truncatingIfNeeded: first >> 48),
            UInt8(truncatingIfNeeded: first >> 40),
            UInt8(truncatingIfNeeded: first >> 32),
            UInt8(truncatingIfNeeded: first >> 24),
            UInt8(truncatingIfNeeded: first >> 16),
            UInt8(truncatingIfNeeded: first >> 8),
            UInt8(truncatingIfNeeded: first),
            UInt8(truncatingIfNeeded: second >> 56),
            UInt8(truncatingIfNeeded: second >> 48),
            UInt8(truncatingIfNeeded: second >> 40),
            UInt8(truncatingIfNeeded: second >> 32),
            UInt8(truncatingIfNeeded: second >> 24),
            UInt8(truncatingIfNeeded: second >> 16),
            UInt8(truncatingIfNeeded: second >> 8),
            UInt8(truncatingIfNeeded: second)
        )
        return EntityID(rawValue: UUID(uuid: tuple))
    }

    private func fnv1a64<S: Sequence>(
        _ bytes: S,
        seed: UInt64
    ) -> UInt64 where S.Element == UInt8 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
