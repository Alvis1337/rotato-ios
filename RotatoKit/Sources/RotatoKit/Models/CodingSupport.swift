import Foundation

/// Decoding helpers so stored JSON keeps loading as fields are added: a missing or mistyped key
/// falls back to the default instead of failing the whole file (DataStore's optX() behaviour).
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }

    func optionalValue<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

/// Decodes an array, dropping elements that fail instead of failing the array
/// (the Kotlin side's mapObjectsSafely).
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            if let e = try? container.decode(Element.self) {
                out.append(e)
            } else {
                _ = try? container.decode(Discard.self)
            }
        }
        elements = out
    }

    private struct Discard: Decodable {}
}

extension String {
    public var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// `ifBlank` from Kotlin: self unless blank, else the fallback.
    public func ifBlank(_ fallback: @autoclosure () -> String) -> String { isBlank ? fallback() : self }

    public var nilIfBlank: String? { isBlank ? nil : self }
}

public func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
