import PSPDFKit
import PSPDFKitUI
import SwiftUI

@main
struct OnboardingPacketApp: App {
    @StateObject private var store: PacketStore

    init() {
        // The license key must be set before any other Nutrient call.
        // Without a key, the SDK runs in trial mode and adds a watermark.
        if let key = LicenseKey.value {
            SDK.setLicenseKey(key)
        }
        _store = StateObject(wrappedValue: PacketStore())
    }

    var body: some Scene {
        WindowGroup {
            PacketView()
                .environmentObject(store)
        }
    }
}

/// Reads the optional Nutrient license key.
///
/// Order: the `NUTRIENT_LICENSE_KEY` environment variable of the running app
/// (for example set in the Xcode scheme), then the `NutrientLicenseKey` entry of
/// Info.plist, which the build fills from the `NUTRIENT_LICENSE_KEY` build setting.
/// Empty means trial mode.
enum LicenseKey {
    static var value: String? {
        let candidates = [
            ProcessInfo.processInfo.environment["NUTRIENT_LICENSE_KEY"],
            Bundle.main.object(forInfoDictionaryKey: "NutrientLicenseKey") as? String,
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") }
    }

    static var isTrial: Bool { value == nil }
}
