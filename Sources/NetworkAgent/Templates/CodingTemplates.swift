//  WHAT: The generated package's `Coding/` folder: how the API's JSON is read and written (its dates above all), and
//        ISO 8601 read by hand, so a stamp with microseconds or with no zone reads as well as one with both.
//  PIN:  NO SHARED ISO8601DateFormatter: it is not Sendable, and it reads neither six fractional digits nor a stamp
//        with no zone, both of which APIs send. The hand reader is a pure function.

enum CodingTemplates {
    /// `__FORMATS__` (the formats, as a Swift array), `__FORMATS_DOC__`, `__NUMBER__` (how a number is read),
    /// `__ENCODE__` (the encoder's date strategy) and `__ENCODE_DOC__` are filled per call.
    static let coding = #"""
    import Foundation

    /// How the __STEM__ API's JSON is read and written. Dates are read in ISO 8601, with or without fractional seconds
    /// and a zone (a stamp with no zone is UTC)__FORMATS_DOC__; a number is read as __NUMBER_DOC__. Dates are written
    /// __ENCODE_DOC__. Keys are each type's own (`CodingKeys`).
    public enum __STEM__Coding {
        /// The `DateFormatter` patterns the API writes dates in beside ISO 8601.
        public static let dateFormats: [String] = __FORMATS__

        /// A decoder for the API's responses.
        public static func decoder() -> JSONDecoder {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Double.self) {
                    return Date(timeIntervalSince1970: __NUMBER__)
                }
                let text = try container.decode(String.self)
                guard let date = date(from: text) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "`\(text)` is not a date the API writes")
                }
                return date
            }
            return decoder
        }

        /// An encoder for the API's request bodies.
        public static func encoder() -> JSONEncoder {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = __ENCODE__
            return encoder
        }

        /// `text` read as a date: ISO 8601 first, then each of `dateFormats`.
        public static func date(from text: String) -> Date? {
            if let date = DateParsing.iso8601(text) { return date }
            for formatter in formatters {
                if let date = formatter.date(from: text) { return date }
            }
            return nil
        }

        private static let formatters: [DateFormatter] = dateFormats.map(formatter)

        private static func formatter(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }

    """#

    static let dateParsing = #"""
    import Foundation

    /// ISO 8601 read by hand: `2026-01-01`, `2026-01-01T09:30:00Z`, `2026-01-01T09:30:00.123456+02:00`,
    /// `2026-01-01 09:30:00.123` (no zone: UTC), any number of fractional digits, `+02`, `+0200` or `+02:00`.
    enum DateParsing {
        static func iso8601(_ text: String) -> Date? {
            let bytes = Array(text.utf8)
            var index = 0

            /// The number in the next `count` digits, or nil (and nothing read) when they are not all digits.
            func digits(_ count: Int) -> Int? {
                guard index + count <= bytes.count else { return nil }
                var value = 0
                for offset in 0..<count {
                    let byte = bytes[index + offset]
                    guard byte >= 48, byte <= 57 else { return nil }
                    value = value * 10 + Int(byte - 48)
                }
                index += count
                return value
            }
            func skip(_ byte: UInt8) -> Bool {
                guard index < bytes.count, bytes[index] == byte else { return false }
                index += 1
                return true
            }

            guard let year = digits(4), skip(45), let month = digits(2), skip(45), let day = digits(2) else { return nil }
            var hour = 0, minute = 0, second = 0, fraction = 0.0, offset = 0
            if index < bytes.count {
                guard [84, 116, 32].contains(bytes[index]) else { return nil }   // T, t or a space
                index += 1
                guard let h = digits(2), skip(58), let m = digits(2) else { return nil }
                hour = h
                minute = m
                if skip(58) {
                    guard let s = digits(2) else { return nil }
                    second = s
                }
                if index < bytes.count, bytes[index] == 46 || bytes[index] == 44 {   // . or ,
                    index += 1
                    var scale = 0.1, count = 0
                    while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                        fraction += Double(bytes[index] - 48) * scale
                        scale /= 10
                        index += 1
                        count += 1
                    }
                    guard count > 0 else { return nil }
                }
                if index < bytes.count {
                    if bytes[index] == 90 || bytes[index] == 122 {   // Z or z
                        index += 1
                    } else if bytes[index] == 43 || bytes[index] == 45 {   // + or -
                        let sign = bytes[index] == 43 ? 1 : -1
                        index += 1
                        guard let hours = digits(2) else { return nil }
                        _ = skip(58)
                        let minutes = digits(2) ?? 0
                        offset = sign * (hours * 3600 + minutes * 60)
                    }
                }
            }
            guard index == bytes.count, (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second <= 60 else {
                return nil
            }
            let seconds = daysFromCivil(year, month, day) * 86_400 + hour * 3600 + minute * 60 + second - offset
            return Date(timeIntervalSince1970: Double(seconds) + fraction)
        }

        /// Days from 1970-01-01 to a day of the proleptic Gregorian calendar (Howard Hinnant's algorithm).
        static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
            let y = month <= 2 ? year - 1 : year
            let era = (y >= 0 ? y : y - 399) / 400
            let yearOfEra = y - era * 400
            let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
            let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
            return era * 146_097 + dayOfEra - 719_468
        }
    }

    """#

    static let indirect = #"""
    import Foundation

    /// A value kept behind a reference, so a type may hold one of itself: a post that shares a post, an account that
    /// moved to another. It reads and writes as its value, in Swift and in JSON, and a nil one leaves its key out.
    @propertyWrapper
    public struct Indirect<Value: Sendable>: Sendable {
        private final class Storage: Sendable {
            let value: Value

            init(_ value: Value) {
                self.value = value
            }
        }

        private var storage: Storage

        public init(wrappedValue: Value) {
            storage = Storage(wrappedValue)
        }

        public var wrappedValue: Value {
            get { storage.value }
            set { storage = Storage(newValue) }
        }
    }

    extension Indirect: Equatable where Value: Equatable {
        public static func == (lhs: Indirect, rhs: Indirect) -> Bool {
            lhs.wrappedValue == rhs.wrappedValue
        }
    }

    extension Indirect: Hashable where Value: Hashable {
        public func hash(into hasher: inout Hasher) {
            hasher.combine(wrappedValue)
        }
    }

    extension Indirect: Decodable where Value: Decodable {
        public init(from decoder: Decoder) throws {
            self.init(wrappedValue: try Value(from: decoder))
        }
    }

    extension Indirect: Encodable where Value: Encodable {
        public func encode(to encoder: Encoder) throws {
            try wrappedValue.encode(to: encoder)
        }
    }

    extension KeyedDecodingContainer {
        /// An optional held `@Indirect` reads as nil when its key is missing, as any optional does.
        public func decode<Wrapped: Decodable & Sendable>(_ type: Indirect<Wrapped?>.Type, forKey key: Key) throws -> Indirect<Wrapped?> {
            Indirect(wrappedValue: try decodeIfPresent(Wrapped.self, forKey: key))
        }
    }

    extension KeyedEncodingContainer {
        /// An optional held `@Indirect` leaves its key out when it is nil, as any optional does.
        public mutating func encode<Wrapped: Encodable & Sendable>(_ value: Indirect<Wrapped?>, forKey key: Key) throws {
            try encodeIfPresent(value.wrappedValue, forKey: key)
        }
    }

    """#
}
