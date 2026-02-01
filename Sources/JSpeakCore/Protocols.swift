import Foundation

public struct SpeechRequest: Codable, Sendable {
    public var id: String
    public var method: String
    public var params: [String: String]?

    public init(id: String, method: String, params: [String: String]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct SpeechResponse: Codable {
    public var id: String
    public var ok: Bool
    public var result: AnyCodable?
    public var error: String?

    public init(id: String, ok: Bool, result: AnyCodable? = nil, error: String? = nil) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }
}

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) {
            value = x
        } else if let x = try? container.decode(Int.self) {
            value = x
        } else if let x = try? container.decode(Bool.self) {
            value = x
        } else if let x = try? container.decode(Double.self) {
            value = x
        } else if let x = try? container.decode([String: AnyCodable].self) {
            value = x.mapValues { $0.value }
        } else if let x = try? container.decode([AnyCodable].self) {
            value = x.map { $0.value }
        } else {
            value = ()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let x = value as? String {
            try container.encode(x)
        } else if let x = value as? Int {
            try container.encode(x)
        } else if let x = value as? Bool {
            try container.encode(x)
        } else if let x = value as? Double {
            try container.encode(x)
        } else {
            // Limited encoding support for scaffold
            try container.encode("AnyCodable(unsupported)")
        }
    }
}
