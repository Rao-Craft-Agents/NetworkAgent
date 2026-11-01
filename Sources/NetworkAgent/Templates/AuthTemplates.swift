//  WHAT: The generated package's `Auth/` folder: how a request proves who sends it, and where tokens are kept, one a
//        host, in the Keychain or in memory.
//  PIN:  A TOKEN BELONGS TO ITS HOST. A client whose base URL moves to another instance looks up that host's token, so
//        it never sends the first host's token anywhere else.

enum AuthTemplates {
    static let authScheme = #"""
    import Foundation

    /// How a request proves who sends it, with the token the client keeps for the request's host.
    public enum AuthScheme: Sendable, Hashable {
        /// Nothing is sent.
        case none
        /// `Authorization: Bearer <token>`: OAuth access tokens and JWTs.
        case bearer
        /// `Authorization: Basic <base64 of the token>`, the token being `user:password`.
        case basic
        /// The token as the value of the header `name` (`X-API-Key`).
        case header(String)
        /// The token as the query parameter `name` (`api_key`).
        case query(String)
    }

    """#

    static let tokenStore = #"""
    import Foundation

    /// Where a client keeps its tokens: one a host, so a client moved to another host never sends the first host's.
    public protocol TokenStore: Sendable {
        /// The token kept for `host` (`example.com`, or `localhost:8080` with a port); nil when there is none.
        func token(for host: String) -> String?
        /// Keeps `token` for `host`; nil forgets it.
        func setToken(_ token: String?, for host: String) throws
    }

    """#

    static let keychainTokenStore = #"""
    import Foundation
    import Security

    /// Tokens kept in the Keychain, one item a host under `service`: they outlive the app, and stay locked until the
    /// device is first unlocked.
    public struct KeychainTokenStore: TokenStore {
        /// What the Keychain said when a token could not be kept.
        public struct Failure: Error, CustomStringConvertible {
            public let status: OSStatus
            public var description: String {
                (SecCopyErrorMessageString(status, nil) as String?) ?? "the Keychain answered \(status)"
            }
        }

        /// The Keychain service the items are kept under.
        public let service: String

        /// A store under `service`: the app's bundle identifier and the package's name when left out.
        public init(service: String = KeychainTokenStore.defaultService) {
            self.service = service
        }

        /// `com.example.app.__MODULE__`.
        public static var defaultService: String {
            (Bundle.main.bundleIdentifier.map { $0 + "." } ?? "") + "__MODULE__"
        }

        public func token(for host: String) -> String? {
            var query = item(for: host)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        public func setToken(_ token: String?, for host: String) throws {
            let query = item(for: host)
            guard let token else {
                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
                return
            }
            let data = Data(token.utf8)
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var added = query
                added[kSecValueData as String] = data
                added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                status = SecItemAdd(added as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw Failure(status: status) }
        }

        private func item(for host: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: host]
        }
    }

    """#

    static let memoryTokenStore = #"""
    import Foundation
    import os

    /// Tokens kept in memory for as long as the store lives: for tests, previews, and a session that should end with
    /// the app.
    public final class MemoryTokenStore: TokenStore {
        private let tokens: OSAllocatedUnfairLock<[String: String]>

        /// A store holding `tokens`, by host.
        public init(_ tokens: [String: String] = [:]) {
            self.tokens = OSAllocatedUnfairLock(initialState: tokens)
        }

        public func token(for host: String) -> String? {
            tokens.withLock { $0[host] }
        }

        public func setToken(_ token: String?, for host: String) {
            tokens.withLock { $0[host] = token }
        }
    }

    """#
}
