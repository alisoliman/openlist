import Foundation

/// Debug review bundles may opt into isolated fixtures through their Info.plist.
/// Normal builds never change store, media, or preference locations.
nonisolated enum ReviewSession {
    static var identifier: String? {
        #if DEBUG
        #if os(iOS)
        // UI tests can't rewrite the Info.plist for each run, but they can
        // set XCUIApplication.launchEnvironment.
        let supplied = ProcessInfo.processInfo.environment["OpenlistReviewSession"]
            ?? Bundle.main.object(forInfoDictionaryKey: "OpenlistReviewSession") as? String
        #else
        let supplied = Bundle.main.object(forInfoDictionaryKey: "OpenlistReviewSession") as? String
        #endif
        guard let value = supplied,
              !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }
        return value
        #else
        return nil
        #endif
    }

    static var defaults: UserDefaults {
        if let identifier, let suite = UserDefaults(suiteName: "solimanali.openlist.review.\(identifier)") { return suite }
        #if OPENLIST_DEV
        return UserDefaults(suiteName: "solimanali.openlist.dev") ?? .standard
        #else
        return .standard
        #endif
    }
}
