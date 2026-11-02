import Foundation

/// Version metadata that works from a `.app` bundle, from `swift run`, and
/// from the test harness (where `Bundle.main` is the test runner, not the app).
public enum SlideSenseVersion {
    /// Keep in sync with the `VERSION` file at the repository root; the build
    /// script stamps the same value into `Info.plist`.
    public static let marketingFallback = "0.1.0"

    public static var marketing: String {
        bundleValue(for: "CFBundleShortVersionString") ?? marketingFallback
    }

    public static var build: String {
        bundleValue(for: "CFBundleVersion") ?? marketingFallback
    }

    /// Only trust version keys that come from our own app bundle.
    private static func bundleValue(for key: String) -> String? {
        let bundle = Bundle.main
        guard bundle.bundleIdentifier == "io.github.slidesense",
              let value = bundle.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}
