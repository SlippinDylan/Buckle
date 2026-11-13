import Foundation

enum UpdateConfiguration: Equatable {
    case disabled
    case enabled(feed: URL, publicKey: Data)

    init(enabled: Bool, feed: String, publicKey: String) throws {
        guard enabled else {
            self = .disabled
            return
        }
        guard let components = URLComponents(string: feed), let url = components.url,
            components.scheme == "https", let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil, components.fragment == nil
        else { throw ConfigurationError.invalidFeed }
        if components.rangeOfPort != nil {
            guard let port = components.port, (1...65535).contains(port) else {
                throw ConfigurationError.invalidFeed
            }
        }
        guard let key = Data(base64Encoded: publicKey), key.count == 32 else {
            throw ConfigurationError.invalidPublicKey
        }
        self = .enabled(feed: url, publicKey: key)
    }

    enum ConfigurationError: Error { case invalidFeed, invalidPublicKey }
}
