import Foundation
import Testing

@testable import BuckleCore

@Test func developmentUpdatesNeedNoFeedOrKey() throws {
    #expect(try UpdateConfiguration(enabled: false, feed: "", publicKey: "") == .disabled)
}

@Test func updatesRequireHTTPSAndAnEd25519PublicKey() throws {
    let key = Data(repeating: 3, count: 32).base64EncodedString()
    for feed in [
        "", "http://example.test/feed.xml", "https:///feed.xml", "https://:443/feed.xml",
        "https://user:password@example.test/feed.xml", "https://example.test/feed.xml#fragment",
        "https://example.test:0/feed.xml", "https://example.test:65536/feed.xml",
        "https://example.test:999999999999999999/feed.xml",
    ] {
        #expect(throws: UpdateConfiguration.ConfigurationError.self) {
            try UpdateConfiguration(enabled: true, feed: feed, publicKey: key)
        }
    }
    for invalidKey in ["", "invalid", Data(repeating: 0, count: 31).base64EncodedString()] {
        #expect(throws: UpdateConfiguration.ConfigurationError.self) {
            try UpdateConfiguration(enabled: true, feed: "https://example.test/feed.xml", publicKey: invalidKey)
        }
    }
    let feed = "https://slippindylan.github.io/homebrew-tap/buckle/appcast.xml"
    let config = try UpdateConfiguration(enabled: true, feed: feed, publicKey: key)
    let url = try #require(URL(string: feed))
    #expect(config == .enabled(feed: url, publicKey: Data(repeating: 3, count: 32)))
}
