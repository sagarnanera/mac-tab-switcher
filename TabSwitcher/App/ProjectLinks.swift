import Foundation

/// Every URL the app can send someone to.
///
/// Collected rather than written at the call site: these are the only outbound
/// destinations in an app that otherwise makes no network connections at all, and a
/// single list is what makes that claim checkable. The repository has already been
/// renamed once, which silently broke every link that had been written by hand.
enum ProjectLinks {
    static let repository = URL(string: "https://github.com/sagarnanera/mac-tab-switcher")!

    /// The issue form, which asks for the diagnostics the bug button puts on the
    /// clipboard just before opening this.
    static let reportBug = URL(
        string: "https://github.com/sagarnanera/mac-tab-switcher/issues/new?template=bug_report.yml"
    )!
}
