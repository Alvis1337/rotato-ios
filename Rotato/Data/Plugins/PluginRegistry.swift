import Foundation

enum PluginRegistry {
    static let all: [any SourcePlugin] = [
        GelbooruPlugin(),
        DanbooruPlugin(),
        WallhavenPlugin(),
        RedditPlugin(),
        Rule34Plugin(),
    ]

    static func plugin(for id: String) -> (any SourcePlugin)? {
        all.first { $0.id == id }
    }
}
