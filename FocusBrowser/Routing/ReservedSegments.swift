/// Path segments that are site vocabulary, not user data. Shared by `PathRedactor` and, in Step 2
/// phase B, by the route classifier: a first segment outside `firstSegments` is a username.
enum ReservedSegments {
    /// Top-level namespaces of the site.
    static let firstSegments: Set<String> = [
        "accounts", "direct", "explore", "reels", "reel", "p", "stories", "challenge",
        "about", "legal", "privacy", "terms", "help", "safety", "press", "web", "api", "graphql",
        "directory", "developer", "emails", "oauth", "session", "login", "logout", "download",
        "tv", "tags", "locations", "nametag", "ajax", "static", "data", "cookies", "security",
        "your_activity", "archive", "professional", "ads", "threads",
    ]

    /// Non-first segments that stay readable in redacted paths; any other one is an id or a name.
    static let knownSubsegments: Set<String> = [
        "inbox", "t", "requests", "new", "general", "hidden",
        "search", "tags", "locations", "people",
        "login", "emailsignup", "password", "reset", "onetap", "edit", "activity", "settings",
        "comments", "liked_by", "reels", "reel", "tagged", "saved", "following", "followers",
        "highlights", "audio", "channel", "guides", "feed", "suggested",
    ]
}
