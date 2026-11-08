import Foundation

/// Whether a pane's Advanced disclosure is open. It starts closed and opens while the
/// Settings search has text, so a search always shows the controls it found. Opening or
/// closing it by hand outside a search is remembered while the pane is open; closing it
/// during a search holds while the search shows that same text, until it is cleared.
public struct AdvancedDisclosureState: Equatable, Sendable {
    private var userExpanded = false
    private var collapsedForQuery: String?

    public init() {}

    public func isExpanded(query: String) -> Bool {
        let search = Self.normalise(query)
        guard !search.isEmpty else { return userExpanded }
        return collapsedForQuery != search
    }

    public mutating func setExpanded(_ expanded: Bool, query: String) {
        let search = Self.normalise(query)
        if search.isEmpty {
            userExpanded = expanded
        } else {
            collapsedForQuery = expanded ? nil : search
        }
    }

    /// Call when the search text changes. An empty search ends the search, so a close made
    /// during it doesn't carry over to the same text typed again later.
    public mutating func searchChanged(to query: String) {
        if Self.normalise(query).isEmpty { collapsedForQuery = nil }
    }

    private static func normalise(_ query: String) -> String {
        query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
