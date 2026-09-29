import Foundation

/// What to do with a navigation, before any route policy is applied.
enum NavigationVerdict: Equatable {
    case allow
    case cancel
    case openInSafari(URL)
}

/// Pure decision logic for navigation hygiene (no WebKit), so it can be unit-tested.
enum NavigationHygiene {
    private static let cancelledSchemes: Set<String> = ["instagram", "itms-apps", "itms-appss", "itms"]
    private static let passthroughSchemes: Set<String> = ["about", "blob", "data"]
    private static let cancelledHosts: Set<String> = ["apps.apple.com"]
    private static let linkShimHost = "l.instagram.com"

    static func verdict(for url: URL?, isMainFrame: Bool) -> NavigationVerdict {
        guard let url, let scheme = url.scheme?.lowercased() else { return .cancel }

        if cancelledSchemes.contains(scheme) { return .cancel }
        if passthroughSchemes.contains(scheme) { return .allow }
        guard scheme == "http" || scheme == "https" else { return .cancel }
        guard let host = url.host?.lowercased() else { return .cancel }

        if cancelledHosts.contains(host) { return .cancel }

        // Subframes (embeds, login helpers) are not our concern.
        guard isMainFrame else { return .allow }

        if host == linkShimHost {
            guard let target = shimTarget(of: url) else { return .cancel }
            return .openInSafari(target)
        }
        if isInstagramHost(host) { return .allow }
        return .openInSafari(url)
    }

    static func isInstagramHost(_ host: String) -> Bool {
        host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    /// `https://l.instagram.com/?u=<encoded target>` → the target, if it is http(s).
    private static func shimTarget(of url: URL) -> URL? {
        guard
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let value = items.first(where: { $0.name == "u" })?.value,
            let target = URL(string: value),
            let scheme = target.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            target.host != nil
        else { return nil }
        return target
    }
}
