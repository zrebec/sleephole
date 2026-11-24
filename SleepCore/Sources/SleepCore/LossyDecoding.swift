import Foundation

/// B61: a journal must survive an event it does not know. `NightEventKind` is a `String` enum, so ONE kind a build
/// has never heard of (a newer build's sync file, a downgrade) used to fail the whole `[NightEvent]` decode – the night
/// journal read empty, the next append overwrote it, a sync file or a backup was refused. The decoders here skip the
/// elements they cannot read (an unknown kind, a malformed element) and keep the others in their order.
/// Encoding is the plain array encoding, byte-identical to `[NightEvent]`.
private struct LossyElement<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

public enum LossyDecoding {
    /// The readable elements of a JSON array, in order. Throws only when the top level is no array at all.
    public static func elements<T: Decodable>(_ type: T.Type, from data: Data, using decoder: JSONDecoder = JSONDecoder()) throws -> [T] {
        try decoder.decode([LossyElement<T>].self, from: data).compactMap(\.value)
    }
}

public extension NightEvent {
    /// The readable events of a stored journal; nil when the bytes are not a JSON array of any kind (nothing can be
    /// told about them, so the caller must not overwrite them).
    static func decodeLossy(_ data: Data, using decoder: JSONDecoder = JSONDecoder()) -> [NightEvent]? {
        try? LossyDecoding.elements(NightEvent.self, from: data, using: decoder)
    }
}

/// `[NightEvent]` that decodes leniently (see `LossyDecoding`) and encodes exactly like the plain array.
@propertyWrapper
public struct LossyNightEvents: Codable, Equatable, Sendable {
    public var wrappedValue: [NightEvent]
    public init(wrappedValue: [NightEvent]) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var events: [NightEvent] = []
        while !container.isAtEnd {
            if let e = try? container.decode(NightEvent.self) {
                events.append(e)
            } else {
                _ = try? container.decode(SkippedElement.self)      // a failed decode does not advance the container
            }
        }
        wrappedValue = events
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for e in wrappedValue { try container.encode(e) }
    }

    private struct SkippedElement: Decodable { init(from decoder: Decoder) throws {} }
}
